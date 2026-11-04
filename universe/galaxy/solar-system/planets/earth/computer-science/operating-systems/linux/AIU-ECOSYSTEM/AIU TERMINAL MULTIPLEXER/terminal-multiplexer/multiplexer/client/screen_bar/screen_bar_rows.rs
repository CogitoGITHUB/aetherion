use super::*;

impl Screen {
    pub(crate) fn take_workspace_quiet(&mut self, record: &Value) {
        if let Some(data) = record.get("outputs").and_then(|outputs| outputs.get("workspace")) {
            let held = data.clone();
            self.take_workspace_data(&held);
        }
    }

    pub(super) fn bar_box(&self) -> Vec<String> {
        let width = self.cols.max(20) as usize;
        let layer = match self.mode {
            Mode::Insert => "write",
            _ => "visual",
        };
        let short = format!("{}", self.focused_tab());
        bar_lines_from_racket(layer, &short, width)
    }
}
