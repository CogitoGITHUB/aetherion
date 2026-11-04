use super::*;

/// Resolution is what one key means.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Resolution {
    /// Command means: run this command.
    Command(Command),
    /// Map means: open this sub-map.
    Map(Context),
    /// Pending means: the key is part of a sequence; wait for the next.
    Pending,
    /// Pass means: the key belongs to the program in the pane.
    Pass,
    /// Ignore means: the key means nothing here.
    Ignore,
}

/// Hit is what one key matched in one map.
pub(crate) enum Hit {
    Exact(Action),
    Partial(Action),
    None,
}

/// Keymap reads the keys and says what they mean. It holds the sequence that
/// is being typed and the map the explorer is showing, and nothing else: the
/// commands themselves do not live here.
pub struct Keymap {
    pub(crate) pending: Vec<u8>,
    pub(crate) group: Option<Context>,
    pub(crate) explorer: Context,
}

