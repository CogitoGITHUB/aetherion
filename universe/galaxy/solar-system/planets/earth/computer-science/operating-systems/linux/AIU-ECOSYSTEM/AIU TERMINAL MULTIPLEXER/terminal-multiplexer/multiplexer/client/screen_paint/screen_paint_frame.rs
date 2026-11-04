use super::*;

impl Screen {
    /// draw answers the whole screen as the escape sequences that draw it.
    pub fn draw(&self) -> String {
        let cols = self.cols.max(20) as usize;
        let rows = self.rows.max(6) as usize;
        // The screen's own furniture takes rows from the programs: the
        // level says how much of it there is, and level 0 leaves the
        // whole screen to the panes.
        let (top, area_rows) = self.area();
        let status = self.status_rows();
        let bar = self.level >= 1 && self.shows_tab_bar;
        let mut out = String::new();
        out.push_str("\x1b[?25l");
        if bar {
            put(&mut out, 1, 1, &clip(&self.tab_bar(), cols));
        }
        let rects = self.rects(self.cols.max(20), area_rows, top);
        let members = self.tab_panes();
        for (at, rect) in rects.iter().enumerate() {
            let index = members[at];
            let focused = index == self.focused;
            let lines = self.pane_lines(index, rect, focused);
            for (row, text) in lines.iter().enumerate() {
                put(&mut out, rect.top + row as u16, rect.left, text);
            }
        }
        // The rows of the screen's own furniture sit at the bottom, and
        // the mode row is the last of them.
        let first = rows.saturating_sub(status.len()) as u16 + 1;
        for (at, line) in status.iter().enumerate() {
            put(&mut out, first + at as u16, 1, &clip(line, cols));
        }
        if let Some(panel) = &self.panel {
            self.draw_panel(&mut out, panel, rows);
        }
        out.push_str("\x1b[0m");
        out
    }

    /// draw_panel draws the box that lies over the panes.
    pub(super) fn draw_panel(&self, out: &mut String, panel: &Panel, rows: usize) {
        let width = panel
            .lines
            .iter()
            .map(|line| line.chars().count())
            .max()
            .unwrap_or(20)
            .max(panel.title.chars().count() + 4)
            .min(self.cols.max(20) as usize - 2);
        let height = panel.lines.len() + 2;
        let top = 2u16;
        let left = 2u16;
        let mut edge = format!("+-- {} ", panel.title);
        while edge.chars().count() + 1 < width {
            edge.push('-');
        }
        edge.push('+');
        put(out, top, left, &edge);
        for (at, line) in panel.lines.iter().enumerate() {
            put(
                out,
                top + 1 + at as u16,
                left,
                &format!("|{}|", clip(line, width.saturating_sub(2))),
            );
        }
        put(out, top + height as u16, left, &format!("+{}+", "-".repeat(width - 2)));
        let _ = rows;
    }

    /// events_line answers the strip that says what just happened: the last
    /// event, and how many are waiting behind it.
    pub(super) fn events_line(&self) -> String {
        match self.events.last() {
            Some(last) => format!("{} ({} events)", last, self.events.len()),
            None => "nothing has happened yet".to_string(),
        }
    }

    /// tab_bar answers the line that names the tabs and marks the one the
    /// owner stands in.
    pub(super) fn tab_bar(&self) -> String {
        if self.tabs.is_empty() {
            return "[no tabs]".to_string();
        }
        let mut line = String::new();
        for (at, tab) in self.tabs.iter().enumerate() {
            if at > 0 {
                line.push(' ');
            }
            if at == self.tab {
                line.push('[');
                line.push_str(tab);
                line.push(']');
            } else {
                line.push_str(tab);
            }
        }
        line
    }

    /// window answers the lines of one pane that the screen shows: the tail
    /// of the pane's words, or the page the owner scrolled to.
    ///
    /// The drawing and the pick read this one window, so a line that is on
    /// the screen is a line that can be picked, and a line that is not on
    /// the screen cannot be picked: it cannot be seen.
    pub(super) fn window(&self, index: usize, height: usize) -> Vec<String> {
        let pane = match self.panes.get(index) {
            Some(pane) => pane,
            None => return Vec::new(),
        };
        let end = pane.lines.len().saturating_sub(pane.scroll);
        let start = end.saturating_sub(height);
        pane.lines[start..end].to_vec()
    }
}
