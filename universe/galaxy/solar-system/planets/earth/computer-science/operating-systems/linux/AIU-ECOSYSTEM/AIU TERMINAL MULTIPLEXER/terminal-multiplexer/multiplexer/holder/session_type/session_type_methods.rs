use crate::*;

impl Session {
    pub(crate) fn screen_client(&self) -> Option<c_int> {
        self.clients
            .iter()
            .find(|client| client.role == "screen" && !client.dead)
            .map(|client| client.fd)
    }

    pub(crate) fn token(&self) -> String {
        if let Ok(from_env) = std::env::var("AIU_MULTIPLEXER_TOKEN") {
            if !from_env.is_empty() {
                return from_env;
            }
        }
        let mut files = vec![self.state_dir.join("token")];
        if let Some(above) = self.state_dir.parent() {
            files.push(above.join("token"));
        }
        for file in files {
            if let Ok(body) = std::fs::read_to_string(&file) {
                let said = body.trim().to_string();
                if !said.is_empty() {
                    return said;
                }
            }
        }
        String::new()
    }

    pub(crate) fn token_matches(&self, given: &str) -> bool {
        if given.is_empty() {
            return false;
        }
        let own = self.token();
        !own.is_empty() && given == own
    }

    pub(crate) fn tab_names(&self) -> Vec<String> {
        if self.tabs.is_empty() {
            return vec![String::new()];
        }
        self.tabs.clone()
    }

    pub(crate) fn sizes(&self) -> Vec<(String, u16, u16)> {
        let mut held: Vec<(String, u16, u16)> = Vec::new();
        for tab in self.tab_names() {
            let members: Vec<&Pane> = self
                .panes
                .iter()
                .filter(|pane| pane.tab == tab)
                .collect();
            if members.is_empty() {
                continue;
            }
            let weights: Vec<u16> = members.iter().map(|pane| pane.weight).collect();
            let rects = geometry::rects(&self.direction, &weights, self.cols, self.area_rows, 1);
            for (pane, rect) in members.iter().zip(rects.iter()) {
                held.push((pane.name.clone(), rect.cols, rect.rows));
            }
        }
        held
    }

    pub(crate) fn tell_sizes(&mut self) -> Vec<String> {
        let sizes = self.sizes();
        let mut told: Vec<String> = Vec::new();
        for (name, cols, rows) in sizes {
            let at = match self.panes.iter().position(|pane| pane.name == name) {
                Some(at) => at,
                None => continue,
            };
            let master = self.panes[at].shell.master;
            let pid = self.panes[at].shell.pid;
            if tty::set_window_size(master, cols, rows).is_ok() {
                unsafe {
                    libc::kill(-pid, libc::SIGWINCH);
                }
                told.push(name);
            }
        }
        told
    }

    pub(crate) fn shape(&self) -> Vec<layout::Pane> {
        self.panes
            .iter()
            .map(|pane| layout::Pane {
                name: pane.name.clone(),
                tab: pane.tab.clone(),
                program: pane.shell.program.clone(),
                weight: pane.weight,
                cols: self.cols,
                rows: self.area_rows,
            })
            .collect()
    }

    pub(crate) fn record(&mut self, fields: Fields) -> Value {
        self.seq += 1;
        let mut map = serde_json::Map::new();
        map.insert("run-id".to_string(), json!(self.run_id));
        map.insert("seq".to_string(), json!(self.seq));
        map.insert("parent-id".to_string(), json!(""));
        map.insert("kind".to_string(), json!(fields.kind));
        map.insert("depth".to_string(), json!(0));
        map.insert("who".to_string(), json!(fields.who));
        map.insert("what".to_string(), json!(fields.what));
        map.insert("why".to_string(), json!(fields.why));
        map.insert("how".to_string(), json!(fields.how));
        map.insert("inputs".to_string(), fields.inputs);
        map.insert("outputs".to_string(), fields.outputs);
        map.insert("result".to_string(), fields.result);
        map.insert("utc".to_string(), json!(utc_now()));
        map.insert("mono-ms".to_string(), json!(self.started.elapsed().as_millis()));
        map.insert("duration-ms".to_string(), json!(0));
        Value::Object(map)
    }

    pub(crate) fn write(&mut self, record: &Value) {
        if let Err(why) = self.log.append(record) {
            eprintln!("holder: {}", why);
            std::process::exit(1);
        }
        self.broadcast(record);
        if !self.log.over_limit() {
            return;
        }
        let note = match self.log.trim() {
            Ok(trimmed) => self.record(Fields {
                kind: "info",
                who: "holder",
                what: "the journal was trimmed",
                why: "the log passed the bound this session keeps to",
                how: "the kept records were written beside the log, synced, and put \
                      in place by a rename; the rule lives in holder/log.rs",
                inputs: json!({ "limit-bytes": trimmed.limit }),
                outputs: json!({
                    "dropped": trimmed.dropped,
                    "kept": trimmed.kept,
                    "from-seq": trimmed.from,
                    "to-seq": trimmed.to,
                }),
                result: json!({}),
            }),
            Err(why) => self.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the journal was not trimmed",
                why: "the bound could not be kept, so the log grows past it",
                how: "the trim was tried once and refused; the session goes on",
                inputs: json!({ "limit-bytes": self.log.rule().0 }),
                outputs: json!({ "bytes": self.log.size() }),
                result: json!({ "why": why }),
            }),
        };
        if let Err(why) = self.log.append(&note) {
            eprintln!("holder: {}", why);
            std::process::exit(1);
        }
        self.broadcast(&note);
    }

    pub(crate) fn broadcast(&mut self, record: &Value) {
        let mut line = record.to_string();
        line.push('\n');
        for client in self.clients.iter_mut() {
            if !client.attached {
                continue;
            }
            if let Err(why) = write_to(client.fd, line.as_bytes()) {
                eprintln!("holder: the client on fd {} is dropped: {}", client.fd, why);
                client.dead = true;
            }
        }
    }

    pub(crate) fn state(&mut self, why: &str) -> Value {
        let attached = self.clients.iter().filter(|c| c.attached).count();
        let workspace_dir = self.workspace_dir.clone();
        let workspace_name = self.workspace.clone();
        let workspace = workspace::read(&workspace_dir, &workspace_name, "list");
        let mut panes: Vec<Value> = Vec::new();
        let mut hidden: Vec<Value> = Vec::new();
        for pane in &self.panes {
            if pane.hidden {
                hidden.push(json!({
                    "name": pane.name.clone(),
                    "tab": pane.tab.clone(),
                    "pid": pane.shell.pid,
                    "alive": pane.shell.alive_now(),
                    "program": pane.shell.program.clone(),
                }));
                continue;
            }
            panes.push(json!({
                "name": pane.name.clone(),
                "tab": pane.tab.clone(),
                "pid": pane.shell.pid,
                "alive": pane.shell.alive_now(),
                "program": pane.shell.program.clone(),
                "weight": pane.weight,
                "text": pane_log_tail(self, &pane.name, 50)
            }));
        }
        self.record(Fields {
            kind: "info",
            who: "holder",
            what: "what this session holds",
            why: why,
            how: "the holder read its own memory and asked the kernel about every pane",
            inputs: json!({}),
            outputs: json!({
                "session": self.run_id.clone(),
                "direction": self.direction.clone(),
                "tabs": Value::Array(
                    self.tabs
                        .iter()
                        .map(|tab| Value::from(tab.clone()))
                        .collect::<Vec<Value>>(),
                ),
                "panes": Value::Array(panes),
                "hidden": Value::Array(hidden),
                "log": self.log_path.display().to_string(),
                "socket": self.socket_path.display().to_string(),
                "state-dir": self.state_dir.display().to_string(),
                "records": self.seq,
                "clients": self.clients.len(),
                "attached": attached,
                "sessions-dir": self.sessions_dir.to_string_lossy(),
                "event-contract": EVENT_CONTRACT,
                "holder-contract": HOLDER_CONTRACT,
                "workspace": workspace.data
            }),
            result: json!({}),
        })
    }
}

