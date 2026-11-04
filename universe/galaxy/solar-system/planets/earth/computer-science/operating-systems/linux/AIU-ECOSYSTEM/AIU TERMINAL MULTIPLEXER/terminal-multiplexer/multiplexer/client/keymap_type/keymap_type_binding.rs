use super::*;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Command(Command),
    Map(Context),
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Need {
    Always,
    AnotherTab,
    AnotherPane,
}

#[derive(Clone, Copy, Debug)]
pub struct State {
    pub tabs: usize,
    pub panes: usize,
}

pub struct Binding {
    pub keys: &'static str,
    pub bytes: &'static [u8],
    pub about: &'static str,
    pub action: Action,
    pub need: Need,
}

impl Binding {
    pub fn available(&self, state: &State) -> bool {
        match self.need {
            Need::Always => true,
            Need::AnotherTab => state.tabs > 1,
            Need::AnotherPane => state.panes > 1,
        }
    }

    pub fn is_map(&self) -> bool {
        matches!(self.action, Action::Map(_))
    }

    #[cfg(test)]
    pub fn action_as_command(&self) -> Option<Command> {
        match self.action {
            Action::Command(command) => Some(command),
            Action::Map(_) => None,
        }
    }
}

