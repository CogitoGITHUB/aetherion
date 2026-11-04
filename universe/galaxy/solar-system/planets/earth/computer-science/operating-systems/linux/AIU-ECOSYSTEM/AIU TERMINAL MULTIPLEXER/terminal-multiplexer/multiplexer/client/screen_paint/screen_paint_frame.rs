use super::*;

impl Screen {
    pub fn draw(&self) -> String {
        let cols = self.cols.max(20) as usize;
        let rows = self.rows.max(6) as usize;
        let (top, area_rows) = self.area();
        let status = self.status_rows();
        let mut out = String::new();
        out.push_str("\x1b[?25l");
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

    pub(super) fn events_line(&self) -> String {
        match self.events.last() {
            Some(last) => format!("{} ({} events)", last, self.events.len()),
            None => "nothing has happened yet".to_string(),
        }
    }

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
