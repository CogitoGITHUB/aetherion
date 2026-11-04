use super::*;

impl Screen {
    /// control_words runs the words an agent sent, the way the owner runs
    /// them: the words are the words of the command line, and the command
    /// line is the owner's own path. It is public because the agent's door
    /// is this screen, and the agent must not get a second set of commands.
    pub fn control_words(&mut self, said: &str) -> Action {
        self.run_command(said)
    }

    /// wait_for_state says the agent's request waits for the state: the
    /// answer the agent gets is the state as it stands.
    pub fn wait_for_state(&mut self, id: String) {
        self.pending = Some(id);
        self.fresh = false;
    }

    /// take_pending answers the agent's request when the state has arrived,
    /// and nothing before: an answer that carries an old picture is a lie
    /// the agent would act on.
    pub fn take_pending(&mut self) -> Option<String> {
        if !self.fresh {
            return None;
        }
        self.fresh = false;
        self.pending.take()
    }

    /// view answers what the screen holds right now: the tabs, the panes
    /// with their text and their scroll, the focus, and the ring of copies.
    /// The agent cannot see the screen, so the screen says what is on it.
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

    /// rewind_to asks the holder how one pane stood at one record. The record
    /// is chosen by its seq — the number the events strip and the records
    /// panel show — and the answer fills a panel over the panes. Nothing is
    /// sent to a pane and nothing is written: a look back cannot change what
    /// the pane is doing.
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

    /// take_rewind fills the panel with how one pane stood at one record: the
    /// journal's own lines, never the live pane's. The panel lies over the
    /// panes, so the live pane keeps its own output while the owner looks.
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
