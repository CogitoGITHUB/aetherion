use super::*;

impl Screen {
    pub(super) fn bar_lists(&self) -> (Vec<String>, Option<usize>, Vec<String>, Option<usize>) {
        let data = match &self.workspace {
            Some(data) => data,
            None => return (Vec::new(), None, Vec::new(), None),
        };
        let id = data.get("workspace").and_then(|value| value.as_str()).unwrap_or("");
        let held: Vec<Value> = data
            .get("workspaces")
            .and_then(|value| value.as_array())
            .cloned()
            .unwrap_or_default();
        let names: Vec<String> = held
            .iter()
            .map(|one| one.get("name").and_then(|value| value.as_str()).unwrap_or("").to_string())
            .collect();
        let at = held
            .iter()
            .position(|one| one.get("id").and_then(|value| value.as_str()) == Some(id));
        let projects: Vec<(String, String)> = match at {
            Some(index) => held[index]
                .get("projects")
                .and_then(|value| value.as_array())
                .map(|list| {
                    list.iter()
                        .map(|one| {
                            (
                                one.get("id").and_then(|value| value.as_str()).unwrap_or("").to_string(),
                                one.get("name").and_then(|value| value.as_str()).unwrap_or("").to_string(),
                            )
                        })
                        .collect()
                })
                .unwrap_or_default(),
            None => Vec::new(),
        };
        let project_at = projects
            .iter()
            .position(|(one_id, one_name)| *one_id == self.project_name || *one_name == self.project_name);
        let project_names: Vec<String> = projects.into_iter().map(|(_, name)| name).collect();
        (names, at, project_names, project_at)
    }

    pub(crate) fn take_workspace_quiet(&mut self, record: &Value) {
        if let Some(data) = record.get("outputs").and_then(|outputs| outputs.get("workspace")) {
            let held = data.clone();
            self.take_workspace_data(&held);
        }
    }

    pub(super) fn bar_box(&self) -> Vec<String> {
        let width = self.cols.max(20) as usize;
        let inner = width.saturating_sub(4).max(1);
        let mut sections: Vec<(String, Vec<String>)> = Vec::new();
        if self.shows_tab_bar {
            let (workspaces, workspace_at, projects, project_at) = self.bar_lists();
            if !workspaces.is_empty() {
                sections.push(("workspace".to_string(), vec![mark_row(&workspaces, workspace_at, inner)]));
            }
            if !projects.is_empty() {
                sections.push(("project".to_string(), vec![mark_row(&projects, project_at, inner)]));
            }
            let tab_text = if self.tabs.is_empty() {
                "no tabs".to_string()
            } else {
                mark_row(&self.tabs, Some(self.tab), inner)
            };
            sections.push(("tabs".to_string(), vec![tab_text]));
        }
        let mut lines: Vec<String> = Vec::new();
        for (at, (title, body)) in sections.iter().enumerate() {
            let (left, right) = if at == 0 { ("╭", "╮") } else { ("├", "┤") };
            lines.push(edge_line(left, right, title, "", width));
            for text in body {
                lines.push(body_line(text, width));
            }
        }
        let layer = match self.mode {
            Mode::Insert => "write",
            _ => "visual",
        };
        let short = format!("{}", self.focused_tab());
        let mut racket = bar_lines_from_racket(layer, &short, width);
        if !lines.is_empty() {
            if let Some(first) = racket.first_mut() {
                *first = first.replacen("╭", "├", 1).replacen("╮", "┤", 1);
            }
        }
        lines.extend(racket);
        lines
    }
}
