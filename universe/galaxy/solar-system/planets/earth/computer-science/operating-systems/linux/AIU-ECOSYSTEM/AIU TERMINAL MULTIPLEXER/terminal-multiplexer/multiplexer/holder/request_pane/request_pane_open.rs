use crate::*;

pub(crate) fn request_pane_open(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let wanted = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let program = request
        .get("program")
        .and_then(|value| value.as_str())
        .unwrap_or("/bin/sh")
        .to_string();
    let name = if wanted.is_empty() {
        format!("pane-{}", session.panes.len() + 1)
    } else {
        wanted
    };
    if session.panes.iter().any(|pane| pane.name == name) {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the pane did not open",
            why: "a pane of that name is already open",
            how: "the name was looked for among the open panes and refused",
            inputs: json!({ "pane": name }),
            outputs: json!({}),
            result: json!({ "why": format!("a pane named {} is already open", name) }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(false);
    }
    let mut args: Vec<String> = request
        .get("args")
        .and_then(|value| value.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(|word| word.to_string()))
                .collect()
        })
        .unwrap_or_default();
    // The context: the tail of the pane's own log, asked of the log
    // itself. The screen never copies the text by hand and never
    // scrapes the drawing: the log is the truth.
    if let Some(context) = request.get("context") {
        let pane_of = context
            .get("pane")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
        let target = context
            .get("target")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
        let why = context
            .get("why")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
        // The selection is the text the owner picked on the
        // screen, when the screen picked one. Without a pick the
        // context is the tail of the pane's own log: the log
        // belongs to the holder, and the screen never copies the
        // text by hand.
        let selection = match context.get("selection").and_then(|value| value.as_str()) {
            Some(picked) => picked.to_string(),
            None => pane_log_tail(session, &pane_of, 50),
        };
        let made = bundle::Bundle::make(
            "aiu-multiplexer",
            "aiu-ecosystem",
            &target,
            &selection,
            "",
            "",
            "",
            &why,
        );
        match made {
            Some(bundle) => {
                let text = bundle.text();
                args.push("--prompt".to_string());
                args.push(text);
                // The send is a record: the log says what was sent,
                // to whom and why, before the pane that carries it
                // opens.
                let record = session.record(Fields {
                    kind: "info",
                    who: "client",
                    what: "the context went to the agent",
                    why: "the owner asked for the agent beside this pane",
                    how: "the bundle was built from the pane's log and the pane was opened with it",
                    inputs: json!({ "pane": name.clone(), "program": program.clone(), "client": client_name(&request) }),
                    outputs: json!({ "target": target, "bytes": selection.len() }),
                    result: json!({ "document": bundle.document() }),
                });
                session.write(&record);
            }
            None => {
                let record = session.record(Fields {
                    kind: "fail",
                    who: "holder",
                    what: "the agent pane did not open",
                    why: "a send needs a reason",
                    how: "the bundle was refused because the why was blank",
                    inputs: json!({ "pane": name.clone(), "program": program.clone() }),
                    outputs: json!({}),
                    result: json!({ "why": "the why of the send was blank" }),
                });
                session.write(&record);
                answer_client(session, at, &record);
                return Ok(false);
            }
        }
    }
    let opened = match shells::Shell::start(&program, &args, session.cols, session.rows) {
        Ok(shell) => shell,
        Err(why) => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the pane did not open",
                why: "the program could not be started",
                how: "the terminal refused the program",
                inputs: json!({ "pane": name, "program": program }),
                outputs: json!({}),
                result: json!({ "why": why }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(false);
        }
    };
    let pid = opened.pid;
    let tab = request
        .get("tab")
        .and_then(|value| value.as_str())
        .filter(|value| !value.is_empty())
        .map(|value| value.to_string())
        .unwrap_or_else(|| {
            session
                .tabs
                .first()
                .cloned()
                .unwrap_or_else(|| "main".to_string())
        });
    if !session.tabs.contains(&tab) {
        session.tabs.push(tab.clone());
    }
    session.panes.push(Pane {
        name: name.clone(),
        tab: tab.clone(),
        weight: 1,
    hidden: false,
        args: args.clone(),
        typed: String::new(),
        shell: opened,
    });
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "a pane opened",
        why: "the client asked for a pane",
        how: "a terminal was opened, the program was started on it, the pane joined the session",
        inputs: json!({ "pane": name, "tab": tab, "program": program, "args": args.len(), "client": client_name(&request) }),
        outputs: json!({ "pid": pid, "panes": session.panes.len() }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
