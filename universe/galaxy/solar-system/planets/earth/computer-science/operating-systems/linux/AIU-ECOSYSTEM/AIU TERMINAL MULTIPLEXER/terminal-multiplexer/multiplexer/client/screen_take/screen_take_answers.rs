use super::*;

impl Screen {
    pub(super) fn show_git(&mut self, want: &str) -> Action {
        self.git_want = want.to_string();
        self.message = format!("the git is being read: {}", want);
        Action::Request(json!({
            "op": "git",
            "what": want
        }))
    }

    pub(super) fn show_workspace(&mut self, view: &str) -> Action {
        self.workspace_view = view.to_string();
        self.message = format!("the workspace is being read: {}", view);
        Action::Request(json!({
            "op": "workspace",
            "what": view
        }))
    }

    pub(super) fn take_workspace(&mut self, record: &Value) {
        let data = match record
            .get("outputs")
            .and_then(|outputs| outputs.get("workspace"))
        {
            Some(data) => data.clone(),
            None => return,
        };
        self.take_workspace_data(&data);
        let lines = crate::workspace::lines(&self.workspace_view, &data);
        self.panel = Some(Panel {
            title: format!("the workspace — {}", self.workspace_view),
            lines,
        });
    }

    pub(super) fn take_workspace_data(&mut self, data: &Value) {
        self.workspace = Some(data.clone());
        let id = data
            .get("workspace")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
        if id.is_empty() {
            self.workspace_name = String::new();
        } else {
            let name = data
                .get("workspaces")
                .and_then(|held| held.as_array())
                .and_then(|held| {
                    held.iter().find(|one| {
                        one.get("id").and_then(|value| value.as_str()) == Some(id.as_str())
                    })
                })
                .and_then(|one| one.get("name").and_then(|value| value.as_str()))
                .unwrap_or(&id)
                .to_string();
            self.workspace_name = name;
        }
        self.project_name = data
            .get("project")
            .and_then(|value| value.as_str())
            .unwrap_or("")
            .to_string();
    }

    pub(super) fn take_editor(&mut self, record: &Value) {
        let data = match record
            .get("outputs")
            .and_then(|outputs| outputs.get("editor"))
        {
            Some(data) => data.clone(),
            None => return,
        };
        let lines = crate::editor::lines(&data);
        self.panel = Some(Panel {
            title: "the editor — what it owns".to_string(),
            lines,
        });
    }

    pub(super) fn take_git(&mut self, record: &Value) {
        let data = match record
            .get("outputs")
            .and_then(|outputs| outputs.get("git"))
        {
            Some(data) => data.clone(),
            None => return,
        };
        self.git = Some(data.clone());
        let lines = crate::git::lines(&self.git_want, &data);
        self.panel = Some(Panel {
            title: format!("the git — {}", self.git_want),
            lines,
        });
    }
}
