use super::*;

impl Screen {
    /// paste_clipboard reads the Android clipboard and pastes it into the
    /// focused pane. A phone without the add-on is told by name, before
    /// anything is written: the script behind it waits for ever there.
    pub(super) fn paste_clipboard(&mut self) -> Action {
        match clipboard::paste() {
            Ok(text) => self.paste_text(text),
            Err(why) => {
                self.message = why;
                Action::Nothing
            }
        }
    }

    /// paste_text puts the clipboard's text into the focused pane, the way
    /// the owner's own paste does. The text is checked before it goes: an
    /// empty clipboard is said, and a paste over the limit is refused with
    /// the numbers instead of being cut.
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

    /// paste_into puts the newest copy into a pane, the way the owner's own
    /// paste does: the text goes to the pane's own program.
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

    /// paste_to_agent sends the newest copy to the agents, the way the
    /// owner's own send does: the bundle carries the text and the why.
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
