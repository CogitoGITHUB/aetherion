use super::*;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Resolution {
    Command(Command),
    Map(Context),
    Pending,
    Pass,
    Ignore,
}

pub(crate) enum Hit {
    Exact(Action),
    Partial(Action),
    None,
}

pub struct Keymap {
    pub(crate) pending: Vec<u8>,
    pub(crate) group: Option<Context>,
    pub(crate) explorer: Context,
}

