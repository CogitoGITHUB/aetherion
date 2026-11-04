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
        let mark = if focused { "● " } else { "" };
        lines.push(edge_line("╭", "╮", &format!("{}{}", mark, self.panes[index].name), "", rect.cols as usize));
        let visible = self.window(index, height);
        let visible = if focused && self.mode == Mode::Select {
            self.select.marked(&visible)
        } else {
            visible
        };
        for line in visible.iter() {
            let clipped = clip(line, inner);
            let shown = escape_free_width(&clipped);
            lines.push(format!("│{}{}│", clipped, " ".repeat(inner.saturating_sub(shown))));
        }
        while lines.len() < height + 1 {
            lines.push(format!("│{}│", " ".repeat(inner)));
        }
        lines.push(rule_line("╰", "╯", rect.cols as usize));
        lines
    }
}

fn escape_free_width(text: &str) -> usize {
    let mut count = 0;
    let mut characters = text.chars();
    while let Some(character) = characters.next() {
        if character as u32 == 27 {
            for next in characters.by_ref() {
                if next.is_ascii_alphabetic() {
                    break;
                }
            }
        } else {
            count += 1;
        }
    }
    count
}
