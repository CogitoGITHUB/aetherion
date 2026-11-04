use super::*;

impl Screen {
    /// focus_height answers how many lines the focused pane shows.
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

    /// scroll_view moves the view of the focused pane by one page: a page is
    /// the height of that pane, and the view stops at the oldest page there
    /// is.
    ///
    /// The wheel is refused (rule 13): there is no mouse in this program,
    /// so the scroll is a key too, and the page keys are that key. The
    /// answer says whether the view moved: a scroll that could not happen
    /// is said, and not hidden.
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

    /// scroll_distance answers how far the focused pane's view is from the
    /// tail of its words.
    pub(super) fn scroll_distance(&self) -> usize {
        self.panes
            .get(self.focused)
            .map(|pane| pane.scroll)
            .unwrap_or(0)
    }

    /// pane_lines answers the lines of one pane: its frame, its name, and
    /// what its program said.
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
        // In the selection the region is shown in reverse video: the text
        // under the keys is the text that is selected.
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
