use super::*;

impl Screen {
    /// change_weight asks the holder for more of the space, or less of it,
    /// for the focused pane: the pane's share is its weight, and the layout
    /// file keeps it.
    pub(super) fn change_weight(&mut self, by: i32) -> Action {
        let pane = self.focused_pane();
        if pane.is_empty() {
            self.message = "there is no pane to change".to_string();
            return Action::Nothing;
        }
        let weight = self
            .panes
            .iter()
            .find(|held| held.name == pane)
            .map(|held| held.weight)
            .unwrap_or(1) as i32;
        let next = (weight + by).max(1) as u16;
        if next as i32 == weight {
            self.message = "the pane already has the smallest share".to_string();
            return Action::Nothing;
        }
        self.message = format!("the pane {} takes {} of the space", pane, next);
        Action::Request(json!({
            "op": "weight",
            "pane": pane,
            "weight": next
        }))
    }

    /// focus_pane gives the focus to the pane with that name.
    pub(super) fn focus_pane(&mut self, name: &str) -> bool {        match self.panes.iter().position(|pane| pane.name == name) {
            Some(at) => {
                self.focused = at;
                self.message = format!("the focus is on {}", name);
                true
            }
            None => {
                self.message = format!("there is no pane named {}", name);
                false
            }
        }
    }

    /// close_panel closes the panel over the panes.
    pub(super) fn close_panel(&mut self) {
        self.panel = None;
    }

    /// move_focus moves the focus to the next or the previous pane of the
    /// current tab.
    pub(super) fn move_focus(&mut self, step: i32) {
        let members = self.tab_panes();
        if members.is_empty() {
            return;
        }
        let at = members
            .iter()
            .position(|index| *index == self.focused)
            .unwrap_or(0) as i32;
        let count = members.len() as i32;
        let next = (at + step).rem_euclid(count) as usize;
        self.focused = members[next];
    }

    /// move_tab moves to the next or the previous tab.
    pub(super) fn move_tab(&mut self, step: i32) {
        if self.tabs.is_empty() {
            return;
        }
        let count = self.tabs.len() as i32;
        let next = (self.tab as i32 + step).rem_euclid(count) as usize;
        self.tab = next;
        let members = self.tab_panes();
        if !members.is_empty() {
            self.focused = members[0];
        }
    }
}
