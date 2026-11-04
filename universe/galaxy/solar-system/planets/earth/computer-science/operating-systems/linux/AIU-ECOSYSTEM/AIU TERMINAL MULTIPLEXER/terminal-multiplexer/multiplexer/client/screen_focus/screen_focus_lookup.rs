use super::*;

impl Screen {
    pub(super) fn tab_panes(&self) -> Vec<usize> {
        if self.tabs.is_empty() {
            return (0..self.panes.len()).collect();
        }
        let tab = self.tabs.get(self.tab).cloned().unwrap_or_default();
        let members: Vec<usize> = self
            .panes
            .iter()
            .enumerate()
            .filter(|(_, pane)| pane.tab == tab)
            .map(|(at, _)| at)
            .collect();
        if members.is_empty() {
            (0..self.panes.len()).collect()
        } else {
            members
        }
    }

    pub fn focused_pane(&self) -> String {
        self.panes
            .get(self.focused)
            .map(|pane| pane.name.clone())
            .unwrap_or_default()
    }

    pub(super) fn focused_tab(&self) -> String {
        self.tabs
            .get(self.tab)
            .cloned()
            .unwrap_or_else(|| "main".to_string())
    }

    pub(super) fn rects(&self, cols: u16, rows: u16, top: u16) -> Vec<geometry::Rect> {
        let members = self.tab_panes();
        let weights: Vec<u16> = members
            .iter()
            .map(|at| self.panes[*at].weight.max(1))
            .collect();
        geometry::rects(&self.direction, &weights, cols, rows, top)
    }
}
