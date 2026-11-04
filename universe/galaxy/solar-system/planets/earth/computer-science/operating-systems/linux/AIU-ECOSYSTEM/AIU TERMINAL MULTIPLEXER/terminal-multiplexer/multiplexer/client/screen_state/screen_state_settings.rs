use super::*;

impl Screen {
    /// set_watch makes this screen a watcher: it is drawn from the same state
    /// and says so in the mode row, and it changes nothing (TODO item 60).
    pub fn set_watch(&mut self, watch: bool) {
        self.watch = watch;
    }

    /// watch_filter answers what a watching screen does with one action:
    /// leaving is done, and every action that would change the session is
    /// refused with the rule in the message. The holder refuses the same
    /// things on its own, so the rule holds on both sides of the wire.
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

    /// set_level is the level the config asks for: how much of the screen's
    /// own furniture is drawn. A value above 3 is not a level, so it is taken
    /// as 3 rather than refused.
    pub fn set_level(&mut self, level: u8) {
        self.level = level.min(3);
    }

    /// level answers how much furniture the screen draws now.
    pub fn level(&self) -> u8 {
        self.level
    }

    /// set_tab_bar says whether the tab bar is drawn at level 1 and above.
    pub fn set_tab_bar(&mut self, on: bool) {
        self.shows_tab_bar = on;
    }

    /// tab_bar_on answers whether the tab bar is drawn at level 1 and above.
    pub fn tab_bar_on(&self) -> bool {
        self.shows_tab_bar
    }
}
