use super::*;

/// Action is what a binding does: run a command, or open a sub-map.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Action {
    Command(Command),
    Map(Context),
}

/// Need is the condition under which a binding can run now.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Need {
    Always,
    /// AnotherTab means the binding needs a second tab to move to.
    AnotherTab,
    /// AnotherPane means the binding needs a second pane to move to.
    AnotherPane,
}

/// State is what the multiplexer holds right now, so a binding can say
/// whether it can run.
#[derive(Clone, Copy, Debug)]
pub struct State {
    pub tabs: usize,
    pub panes: usize,
}

/// Binding is one key (or one sequence) and what it means.
pub struct Binding {
    /// keys is what the explorer shows: the key, or the sequence.
    pub keys: &'static str,
    /// bytes is what the keyboard sends for it, the whole sequence.
    pub bytes: &'static [u8],
    /// about is one line about what it does.
    pub about: &'static str,
    /// action is what it does: a command, or a sub-map.
    pub action: Action,
    /// need is what it needs to be able to run now.
    pub need: Need,
}

impl Binding {
    /// available answers whether this binding can run in this state, so the
    /// explorer can say "not now" instead of pretending.
    pub fn available(&self, state: &State) -> bool {
        match self.need {
            Need::Always => true,
            Need::AnotherTab => state.tabs > 1,
            Need::AnotherPane => state.panes > 1,
        }
    }

    /// is_map answers whether this binding opens a sub-map instead of running
    /// a command.
    pub fn is_map(&self) -> bool {
        matches!(self.action, Action::Map(_))
    }

    /// action_as_command answers the command this binding runs, when it runs
    /// one.
    #[cfg(test)]
    pub fn action_as_command(&self) -> Option<Command> {
        match self.action {
            Action::Command(command) => Some(command),
            Action::Map(_) => None,
        }
    }
}

