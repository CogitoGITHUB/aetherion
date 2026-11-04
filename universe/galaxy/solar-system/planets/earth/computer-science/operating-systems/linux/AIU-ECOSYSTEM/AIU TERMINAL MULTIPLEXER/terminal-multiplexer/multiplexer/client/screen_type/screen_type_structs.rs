use super::*;

pub enum Ending {
    Left,
    Refused(String),
    Switch(std::path::PathBuf),
}

pub enum Action {
    Nothing,
    Send(Vec<u8>),
    Request(Value),
    Quit,
    AskEditor,
    Switch(String),
    Terminal(Vec<u8>),
}

pub struct PaneView {
    pub name: String,
    pub tab: String,
    pub weight: u16,
    pub lines: Vec<String>,
    pub scroll: usize,
}

pub(crate) struct Panel {
    pub(crate) title: String,
    pub(crate) lines: Vec<String>,
}

pub struct Screen {
    pub direction: String,
    pub tabs: Vec<String>,
    pub tab: usize,
    pub panes: Vec<PaneView>,
    pub focused: usize,
    pub mode: Mode,
    pub command: String,
    pub cols: u16,
    pub rows: u16,
    pub agent_program: String,
    pub editor_program: String,
    pub message: String,
    pub events: Vec<String>,
    pub select: Selection,
    pub ring: Vec<String>,
    pub(crate) keymap: Keymap,
    pub(crate) panel: Option<Panel>,
    pub(crate) git: Option<Value>,
    pub(crate) git_want: String,
    pub(crate) workspace: Option<Value>,
    pub(crate) workspace_view: String,
    pub(crate) workspace_name: String,
    pub(crate) sessions_dir: String,
    pub(crate) project_name: String,
    pub(crate) level: u8,
    pub(crate) shows_tab_bar: bool,
    pub(crate) workspace_quiet: bool,
    pub(crate) reserved: bool,
    pub(crate) editor_mcp: Vec<String>,
    pub(crate) pending: Option<String>,
    pub(crate) fresh: bool,
    pub(crate) pending_focus: Option<String>,
    pub(crate) watch: bool,
}

