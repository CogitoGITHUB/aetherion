use super::*;

impl Screen {
    pub fn control_words(&mut self, said: &str) -> Action {
        self.run_command(said)
    }

    pub fn wait_for_state(&mut self, id: String) {
        self.pending = Some(id);
        self.fresh = false;
    }

    pub fn take_pending(&mut self) -> Option<String> {
        if !self.fresh {
            return None;
        }
        self.fresh = false;
        self.pending.take()
    }

    pub fn view(&self) -> Value {
        let mut panes: Vec<Value> = Vec::new();
        for pane in &self.panes {
            let first = pane.lines.len().saturating_sub(VIEW_LINES);
            let mut text: Vec<String> = Vec::new();
            for (at, line) in pane.lines.iter().enumerate().skip(first) {
                text.push(format!("{}: {}", at + 1, line));
            }
            panes.push(json!({
                "name": pane.name.clone(),
                "tab": pane.tab.clone(),
                "scroll": pane.scroll,
                "lines": pane.lines.len(),
                "text": text
            }));
        }
        json!({
            "tabs": self.tabs.clone(),
            "tab": self.tab,
            "focused": self.focused_pane(),
            "panes": panes,
            "ring": self.ring.clone(),
            "message": self.message.clone()
        })
    }

    pub(super) fn rewind_to(&mut self, pane: &str, seq: &str) -> Action {
        let wanted: u64 = match seq.parse() {
            Ok(found) => found,
            Err(_) => {
                self.message = format!("{} is not a record number", seq);
                return Action::Nothing;
            }
        };
        if !self.panes.iter().any(|held| held.name == pane) {
            self.message = format!("there is no pane named {}", pane);
            return Action::Nothing;
        }
        self.message = format!("the pane {} is being read back to record {}", pane, wanted);
        Action::Request(json!({ "op": "rewind", "pane": pane, "seq": wanted }))
    }

    pub(super) fn take_rewind(&mut self, record: &Value) {
        let outputs = match record.get("outputs") {
            Some(found) => found,
            None => return,
        };
        let pane = outputs
            .get("pane")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
        let seq = outputs.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
        let lines: Vec<String> = outputs
            .get("lines")
            .and_then(|value| value.as_array())
            .map(|list| {
                list.iter()
                    .filter_map(|one| one.as_str().map(|text| text.to_string()))
                    .collect()
            })
            .unwrap_or_default();
        let mut shown: Vec<String> = vec![
            String::new(),
            format!(
                "  the live pane is not changed — {} as it stood at record {}",
                pane, seq
            ),
            String::new(),
        ];
        if lines.is_empty() {
            shown.push("  that pane had said nothing by that record".to_string());
        }
        for line in &lines {
            shown.push(format!("  {}", line));
        }
        shown.push(String::new());
        shown.push("  the panel stays until another one replaces it".to_string());
        self.panel = Some(Panel {
            title: format!("the rewind — {} at record {}", pane, seq),
            lines: shown,
        });
        self.message = format!(
            "the pane {} was read back to record {}: the live pane is untouched",
            pane, seq
        );
    }
}
