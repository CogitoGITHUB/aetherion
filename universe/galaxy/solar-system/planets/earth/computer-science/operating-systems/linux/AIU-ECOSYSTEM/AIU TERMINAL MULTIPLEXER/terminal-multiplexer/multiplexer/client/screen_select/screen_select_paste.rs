use super::*;

impl Screen {
    pub(super) fn paste_clipboard(&mut self) -> Action {
        match clipboard::paste() {
            Ok(text) => self.paste_text(text),
            Err(why) => {
                self.message = why;
                Action::Nothing
            }
        }
    }

    pub(super) fn paste_text(&mut self, text: String) -> Action {
        if text.is_empty() {
            self.message = "the Android clipboard is empty: nothing is pasted".to_string();
            return Action::Nothing;
        }
        if let Err(why) = clipboard::fits(&text) {
            self.message = why;
            return Action::Nothing;
        }
        let name = self.focused_pane();
        if !self.panes.iter().any(|pane| pane.name == name) {
            self.message = format!("there is no pane named {}", name);
            return Action::Nothing;
        }
        self.message = format!(
            "the Android clipboard ({} bytes) is on its way to {}",
            text.len(),
            name
        );
        Action::Request(json!({
            "op": "send",
            "pane": name,
            "data": text
        }))
    }

    pub(super) fn paste_into(&mut self, name: &str) -> Action {
        let text = match self.ring.first() {
            Some(found) => found.clone(),
            None => {
                self.message = "the ring is empty: nothing was copied".to_string();
                return Action::Nothing;
            }
        };
        if !self.panes.iter().any(|pane| pane.name == name) {
            self.message = format!("there is no pane named {}", name);
            return Action::Nothing;
        }
        self.message = format!("the copy is on its way to {}", name);
        Action::Request(json!({
            "op": "send",
            "pane": name,
            "data": text
        }))
    }

    pub(super) fn paste_to_agent(&mut self) -> Action {
        let text = match self.ring.first() {
            Some(found) => found.clone(),
            None => {
                self.message = "the ring is empty: nothing was copied".to_string();
                return Action::Nothing;
            }
        };
        let program = self.agent_program.clone();
        let target = agent_name(&program);
        let pane = self.focused_pane();
        self.message = "the copy is on its way to the agents".to_string();
        Action::Request(json!({
            "op": "send-agent",
            "selection": text,
            "target": target,
            "from": pane,
            "why": "the agent sent the copied text to the agents"
        }))
    }
}
