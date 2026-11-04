use super::*;

impl Screen {
    pub fn state(&self) -> State {
        State {
            tabs: self.tabs.len(),
            panes: self.panes.len(),
        }
    }

    pub fn take_state(&mut self, record: &Value) {
        let outputs = match record.get("outputs") {
            Some(found) => found,
            None => return,
        };
        if let Some(dir) = outputs.get("sessions-dir").and_then(|one| one.as_str()) {
            self.sessions_dir = dir.to_string();
        }
        if outputs.get("session").is_none() || outputs.get("panes").is_none() {
            return;
        }
        self.fresh = true;
        if let Some(direction) = outputs.get("direction").and_then(|value| value.as_str()) {
            self.direction = direction.to_string();
        }
        let mut tabs: Vec<String> = Vec::new();
        if let Some(list) = outputs.get("tabs").and_then(|value| value.as_array()) {
            for tab in list {
                if let Some(name) = tab.as_str() {
                    tabs.push(name.to_string());
                }
            }
        }
        if !tabs.is_empty() {
            self.tabs = tabs;
        }
        let mut panes: Vec<PaneView> = Vec::new();
        if let Some(list) = outputs.get("panes").and_then(|value| value.as_array()) {
            for pane in list {
                let name = pane
                    .get("name")
                    .and_then(|value| value.as_str())
                    .unwrap_or("")
                    .to_string();
                let tab = pane
                    .get("tab")
                    .and_then(|value| value.as_str())
                    .unwrap_or("main")
                    .to_string();
                let weight = pane
                    .get("weight")
                    .and_then(|value| value.as_u64())
                    .unwrap_or(1) as u16;
                let mut lines = self
                    .panes
                    .iter()
                    .find(|held| held.name == name)
                    .map(|held| held.lines.clone())
                    .unwrap_or_default();
                if lines.is_empty() {
                    if let Some(text) = pane.get("text").and_then(|value| value.as_str()) {
                        for line in text.lines() {
                            lines.push(line.to_string());
                        }
                    }
                }
                let scroll = self
                    .panes
                    .iter()
                    .find(|held| held.name == name)
                    .map(|held| held.scroll)
                    .unwrap_or(0);
                panes.push(PaneView {
                    name,
                    tab,
                    weight,
                    lines,
                    scroll,
                });
            }
        }
        if let Some(workspace) = outputs.get("workspace") {
            self.take_workspace_data(workspace);
        }
        if self.focused >= panes.len() {
            self.focused = 0;
        }
        self.panes = panes;
        if let Some(wanted) = self.pending_focus.clone() {
            if let Some(at) = self.panes.iter().position(|pane| pane.name == wanted) {
                self.focused = at;
                self.pending_focus = None;
            }
        }
    }

    pub fn push_text(&mut self, pane: &str, text: &str) {
        if let Some(held) = self.panes.iter_mut().find(|held| held.name == pane) {
            for line in text.lines() {
                held.lines.push(line.to_string());
            }
            if held.lines.len() > KEPT {
                let extra = held.lines.len() - KEPT;
                held.lines.drain(0..extra);
            }
        }
    }
}
