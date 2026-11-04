#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Visual,
    Insert,
    Command,
    Explorer,
    Select,
}

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

