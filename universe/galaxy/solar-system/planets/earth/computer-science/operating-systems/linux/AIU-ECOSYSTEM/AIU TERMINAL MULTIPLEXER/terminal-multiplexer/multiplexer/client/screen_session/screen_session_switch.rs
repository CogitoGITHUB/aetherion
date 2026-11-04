use super::*;

impl Screen {
    /// show_explorer fills the panel with the keys of the map the explorer is
    /// showing. The panel is made of the keymap's own table, so it cannot
    /// fall behind it.
    pub(super) fn show_explorer(&mut self) {
        let map = self.keymap.explorer_map();
        let state = self.state();
        let mut lines: Vec<String> = Vec::new();
        for binding in bindings(map) {
            let mut line = format!("  {:<8} {}", binding.keys, binding.about);
            if binding.is_map() {
                line.push_str("  → a group");
            }
            if !binding.available(&state) {
                line.push_str("  (not now)");
            }
            lines.push(line);
        }
        lines.push(String::new());
        if map == Context::Select {
            lines.push("  Escape leaves the selection and does nothing else".to_string());
        } else {
            lines.push("  Escape goes back one level".to_string());
        }
        let pending = self.keymap.pending_keys();
        if !pending.is_empty() {
            lines.push(format!("  typing: {}", pending));
        }
        self.panel = Some(Panel {
            title: format!("the keymap — {}", map.title()),
            lines,
        });
    }

    /// show_records fills the panel with the records of this session.
    pub(super) fn show_records(&mut self) {
        let mut lines: Vec<String> = Vec::new();
        for event in self.events.iter().rev().take(20).rev() {
            lines.push(format!("  {}", event));
        }
        if lines.is_empty() {
            lines.push("  nothing has happened yet".to_string());
        }
        self.panel = Some(Panel {
            title: "the records".to_string(),
            lines,
        });
    }

    /// show_sessions fills the panel with the sessions this multiplexer knows.
    /// show_sessions asks the holder what stands: the sessions are the
    /// holder's, and the list is read, never guessed.
    pub(super) fn show_sessions(&mut self) -> Action {
        self.message = "the sessions are being listed".to_string();
        Action::Request(json!({ "op": "sessions" }))
    }

    /// take_sessions fills the panel with what the holder says stands: every
    /// session and whether a holder holds it.
    pub(super) fn take_sessions(&mut self, record: &Value) {
        let mut lines: Vec<String> = Vec::new();
        let sessions = record
            .get("outputs")
            .and_then(|outputs| outputs.get("sessions"))
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();
        for one in &sessions {
            let name = one.get("session").and_then(|v| v.as_str()).unwrap_or("");
            let held = one.get("held").and_then(|v| v.as_bool()).unwrap_or(false);
            let why = one.get("why").and_then(|v| v.as_str()).unwrap_or("");
            if held {
                lines.push(format!("  {} — a holder holds it", name));
            } else {
                lines.push(format!("  {} — {}", name, why));
            }
        }
        if lines.is_empty() {
            lines.push("  no session stands in this directory yet".to_string());
        }
        self.panel = Some(Panel {
            title: "the sessions".to_string(),
            lines,
        });
        self.message = format!("the sessions stand: {}", sessions.len());
    }

    /// session_word asks the holder to run one of the session commands:
    /// create, rename or kill.
    pub(super) fn session_word(&mut self, what: &str, name: &str) -> Action {
        if name.is_empty() || name.contains('/') {
            self.message = format!("{} is not a session name", name);
            return Action::Nothing;
        }
        self.message = format!("the session {} is being asked for {}", name, what);
        Action::Request(json!({ "op": "session", "what": what, "name": name }))
    }

    /// switch_to moves this client to another session's socket: the sessions
    /// directory is the holder's answer, and the name is one of its entries.
    pub(super) fn switch_to(&mut self, name: &str) -> Action {
        if name.is_empty() || name.contains('/') {
            self.message = format!("{} is not a session name", name);
            return Action::Nothing;
        }
        if self.sessions_dir.is_empty() {
            self.message =
                "the holder did not say where the sessions stand, so nothing is switched"
                    .to_string();
            return Action::Nothing;
        }
        self.message = format!("the client is switching to the session {}", name);
        Action::Switch(name.to_string())
    }
}
