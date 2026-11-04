/// Mode is whose keys these are.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// Visual is the multiplexer's own: the keys are commands.
    Visual,
    /// Insert is the pane's own: the keys are text.
    Insert,
    /// Command is the command line: the keys are words.
    Command,
    /// Explorer is the keymap explorer: the keys walk the keymap.
    Explorer,
    /// Select is the selection overlay: the keys pick the visible text.
    Select,
}

/// Context is which map the keys are read against.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Context {
    Root,
    Tabs,
    Panes,
    Commands,
    Sessions,
    Git,
    Workspace,
    Select,
}

impl Context {
    /// title is what the explorer calls this map.
    pub fn title(&self) -> &'static str {
        match self {
            Context::Root => "the root map",
            Context::Tabs => "the tabs",
            Context::Panes => "the panes",
            Context::Commands => "the commands",
            Context::Sessions => "the sessions",
            Context::Git => "the git",
            Context::Workspace => "the workspace",
            Context::Select => "the selection",
        }
    }

    /// prefix is the key that opens this map, and the first key of every
    /// sequence in it.
    pub fn prefix(&self) -> &'static [u8] {
        match self {
            Context::Root => b"",
            Context::Tabs => b"t",
            Context::Panes => b"p",
            Context::Commands => b"c",
            Context::Sessions => b"s",
            Context::Git => b"g",
            Context::Workspace => b"w",
            Context::Select => b"",
        }
    }
}

