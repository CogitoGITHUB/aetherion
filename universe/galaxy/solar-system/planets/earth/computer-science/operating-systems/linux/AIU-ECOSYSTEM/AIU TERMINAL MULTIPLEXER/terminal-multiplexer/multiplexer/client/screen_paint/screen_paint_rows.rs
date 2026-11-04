use super::*;

impl Screen {
    /// mode_line answers the line at the bottom: the mode, the tab, the
    /// focused pane, the size of the window, and the keys that are free now.
    pub(super) fn mode_line(&self) -> String {
        if self.mode == Mode::Command {
            return format!(":{}", self.command);
        }
        // The message the client answers with stands next to the mode:
        // the row is cut at the end, so what the owner must read is at
        // the front.
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

    /// specifics_line answers the row that says where the owner stands in
    /// the session: the tab, the focused pane and the window size.
    pub(super) fn specifics_line(&self) -> String {
        format!(
            "tab {} -- pane {} -- {}x{}",
            self.focused_tab(),
            self.focused_pane(),
            self.cols,
            self.rows
        )
    }

    /// hints_line answers the row that says what the keys do in this mode.
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

    /// area answers where the panes stand: the row they start at, and how
    /// many rows they have. The screen's own furniture takes the rest, and
    /// the level says how much furniture that is.
    pub(super) fn area(&self) -> (u16, u16) {
        let rows = self.rows.max(6);
        let bar = self.level >= 1 && self.shows_tab_bar;
        let top = if bar { 2 } else { 1 };
        let furniture = self.status_rows().len() + if bar { 1 } else { 0 };
        (top, rows.saturating_sub(furniture as u16))
    }

    /// status_rows answers the screen's own rows at the bottom, from the
    /// top of the block down: the events, the specifics, the hints and the
    /// mode row. The level says which of them are there, and the mode row
    /// is the last one, so it is the row nearest the owner's hands.
    pub(super) fn status_rows(&self) -> Vec<String> {
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

    /// mode_name answers the name of the mode, the way the mode line shows it.
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
