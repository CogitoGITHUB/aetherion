use super::*;

impl Screen {
    pub(super) fn focus_height(&self) -> usize {
        let cols = self.cols.max(20);
        let (top, area_rows) = self.area();
        let rects = self.rects(cols, area_rows, top);
        let members = self.tab_panes();
        let at = match members.iter().position(|index| *index == self.focused) {
            Some(at) => at,
            None => return 0,
        };
        match rects.get(at) {
            Some(rect) => rect.rows.saturating_sub(2) as usize,
            None => 0,
        }
    }

    pub(super) fn scroll_view(&mut self, up: bool) -> bool {
        let height = self.focus_height();
        if height == 0 {
            return false;
        }
        let index = self.focused;
        let (total, current) = match self.panes.get(index) {
            Some(pane) => (pane.lines.len(), pane.scroll),
            None => return false,
        };
        let most = total.saturating_sub(height);
        let next = if up {
            current.saturating_add(height).min(most)
        } else {
            current.saturating_sub(height)
        };
        if let Some(pane) = self.panes.get_mut(index) {
            pane.scroll = next;
        }
        next != current
    }

    pub(super) fn scroll_distance(&self) -> usize {
        self.panes
            .get(self.focused)
            .map(|pane| pane.scroll)
            .unwrap_or(0)
    }

    pub(super) fn pane_lines(&self, index: usize, rect: &geometry::Rect, focused: bool) -> Vec<String> {
        let inner = rect.cols.saturating_sub(2) as usize;
        let height = rect.rows.saturating_sub(2) as usize;
        let mut lines: Vec<String> = Vec::new();
        let name = format!("{} ", self.panes[index].name);
        let mark = if focused { "*" } else { " " };
        let mut top = format!("+{}{}", mark, name);
        while top.chars().count() + 1 < rect.cols as usize {
            top.push('-');
        }
        top.push('+');
        lines.push(top);
        let visible = self.window(index, height);
        let visible = if focused && self.mode == Mode::Select {
            self.select.marked(&visible)
        } else {
            visible
        };
        for line in visible.iter() {
            lines.push(format!("|{}|", clip(line, inner)));
        }
        while lines.len() < height + 1 {
            lines.push(format!("|{}|", " ".repeat(inner)));
        }
        lines.push(format!("+{}+", "-".repeat(inner)));
        lines
    }
}
