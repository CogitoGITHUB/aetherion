use super::*;

impl Screen {
    pub(super) fn mode_line(&self) -> String {
        if self.mode == Mode::Command {
            return format!(":{}", self.command);
        }
        let name = if self.watch {
            format!("WATCH/{}", self.mode_name())
        } else {
            self.mode_name().to_string()
        };
        let mut line = format!("-- {} L{} -- ", name, self.level);
        if !self.workspace_name.is_empty() {
            line.push_str(&format!("ws:{} ", self.workspace_name));
            if !self.project_name.is_empty() {
                line.push_str(&format!("pr:{} ", self.project_name));
            }
            line.push_str("-- ");
        }
        if !self.message.is_empty() {
            line.push_str(&self.message);
            line.push_str(" -- ");
        }
        line.trim_end().to_string()
    }

    pub(super) fn specifics_line(&self) -> String {
        format!(
            "tab {} -- pane {} -- {}x{}",
            self.focused_tab(),
            self.focused_pane(),
            self.cols,
            self.rows
        )
    }

    pub(super) fn hints_line(&self) -> String {
        if self.watch {
            return "this client watches the session: it cannot change it".to_string();
        }
        match self.mode {
            Mode::Visual => {
                let pending = self.keymap.pending_keys();
                if pending.is_empty() {
                    "Space:keys  i:type  ::command  l:less  L:more  pg:page  q:leave".to_string()
                } else {
                    format!("{} …", pending)
                }
            }
            Mode::Insert => "esc:visual".to_string(),
            Mode::Command => String::new(),
            Mode::Explorer => "esc:back  any key of the map".to_string(),
            Mode::Select => "m:mark  y:copy  s:send  p o:agent  pg:page  esc:leave".to_string(),
        }
    }

    pub(super) fn area(&self) -> (u16, u16) {
        let rows = self.rows.max(6);
        let furniture = self.status_rows().len();
        (1, rows.saturating_sub(furniture as u16))
    }

    pub(super) fn status_rows(&self) -> Vec<String> {
        if self.level >= 1 {
            return self.bar_box();
        }
        let mut rows: Vec<String> = Vec::new();
        if self.level >= 2 {
            rows.push(self.events_line());
            rows.push(self.specifics_line());
        }
        if self.level >= 3 {
            rows.push(self.hints_line());
        }
        if self.level >= 1 {
            rows.push(self.mode_line());
        }
        rows
    }

    pub(super) fn mode_name(&self) -> &'static str {
        match self.mode {
            Mode::Visual => "VISUAL",
            Mode::Insert => "INSERT",
            Mode::Command => "COMMAND",
            Mode::Explorer => "KEYS",
            Mode::Select => "SELECT",
        }
    }
}
