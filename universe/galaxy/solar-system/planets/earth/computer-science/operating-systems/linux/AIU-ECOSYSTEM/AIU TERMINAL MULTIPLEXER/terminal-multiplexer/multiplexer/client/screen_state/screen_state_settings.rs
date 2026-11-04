use super::*;

impl Screen {
    pub fn set_watch(&mut self, watch: bool) {
        self.watch = watch;
    }

    pub fn watch_filter(&mut self, action: Action) -> Option<Action> {
        if !self.watch {
            return Some(action);
        }
        match action {
            Action::Quit => Some(Action::Quit),
            _ => {
                self.message = "this client watches the session: it cannot change it"
                    .to_string();
                None
            }
        }
    }

    pub fn set_level(&mut self, level: u8) {
        self.level = level.min(3);
    }

    #[cfg(test)]
    pub fn level(&self) -> u8 {
        self.level
    }

    pub fn set_tab_bar(&mut self, on: bool) {
        self.shows_tab_bar = on;
    }

    #[cfg(test)]
    pub fn tab_bar_on(&self) -> bool {
        self.shows_tab_bar
    }
}
