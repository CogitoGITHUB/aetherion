use super::*;

/// Ending is how the screen's life ended: the owner left, or the holder
/// refused the contracts and said why (TODO item 48).
pub enum Ending {
    /// Left is the owner's own leaving: the session goes on without them.
    Left,
    /// Refused is the holder's answer to a client whose contracts differ, in
    /// the holder's own words plus what to do about it.
    Refused(String),
    /// Switch is the owner moving this client to another session's socket
    /// (TODO item 49).
    Switch(std::path::PathBuf),
}

/// Action is what the client does with the holder after a key.
pub enum Action {
    Nothing,
    /// Send puts the bytes into the focused pane's own program.
    Send(Vec<u8>),
    /// Request asks the holder to do one thing.
    Request(Value),
    /// Quit leaves the multiplexer; the session goes on.
    Quit,
    /// AskEditor asks the editor what it owns, over the editor's own MCP
    /// server: the answer comes back as the editor's own words.
    AskEditor,
    /// Switch leaves this session's screen and attaches to another session.
    Switch(String),
    /// Terminal writes bytes to the owner's own terminal, never to a pane:
    /// the Android clipboard's sequence goes there, and a pane's program
    /// would print it instead of the clipboard taking it.
    Terminal(Vec<u8>),
}

/// PaneView is one pane as the screen sees it: its name, its tab, how much
/// of the layout it wants, and what its program said.
pub struct PaneView {
    pub name: String,
    pub tab: String,
    pub weight: u16,
    pub lines: Vec<String>,
    /// scroll is how many lines the view is back from the tail of the
    /// pane's lines. Zero is the tail: the newest words. The page keys
    /// move it, and the view shows the page the owner scrolled to.
    pub scroll: usize,
}

/// Panel is the box that lies over the panes: the keymap explorer, the
/// records, or the sessions.
pub(crate) struct Panel {
    pub(crate) title: String,
    pub(crate) lines: Vec<String>,
}

/// Screen is what the owner sees: the tabs, the panes of the current tab, the
/// focus, the mode, the command line, and the size of the window.
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
    /// select is the selection: the point, the mark and the region.
    pub select: Selection,
    /// ring is the multiplexer's own ring: what was copied, newest first.
    pub ring: Vec<String>,
    pub(crate) keymap: Keymap,
    pub(crate) panel: Option<Panel>,
    /// git is what the shared layer answered, and git_want is which view
    /// was asked for.
    pub(crate) git: Option<Value>,
    pub(crate) git_want: String,
    /// workspace is what the shared engine answered, and workspace_view is
    /// which view was asked for.
    pub(crate) workspace: Option<Value>,
    pub(crate) workspace_view: String,
    /// workspace_name is the workspace this session works on, and
    /// project_name is the project the context stands on. The mode line
    /// names both.
    pub(crate) workspace_name: String,
    /// sessions_dir is where this session stands with its siblings, as the
    /// holder said: a switch names another one in it (TODO item 49).
    pub(crate) sessions_dir: String,
    pub(crate) project_name: String,
    /// level is how much of the screen's own furniture is drawn. Level 1
    /// is the mode row and the tab bar; level 2 adds the specifics and
    /// the events; level 3 adds the hints. Level 0 draws no furniture at
    /// all: the panes take the whole screen, and the owner asked for
    /// that.
    pub(crate) level: u8,
    /// shows_tab_bar says whether the tab bar is drawn at level 1 and
    /// above. The config asks for it; level 0 hides it whatever the
    /// config says.
    pub(crate) shows_tab_bar: bool,
    /// reserved says that the owner pressed the reserved prefix: the next
    /// key is the multiplexer's own, whatever mode stands.
    pub(crate) reserved: bool,
    /// editor_mcp is the command that starts the editor's own MCP server:
    /// the program and what it runs. It is the seam the multiplexer asks
    /// the editor through.
    pub(crate) editor_mcp: Vec<String>,
    /// pending is the agent's request that waits for the state: the answer
    /// the agent gets is the state as it stands, not the state as it was.
    pub(crate) pending: Option<String>,
    /// fresh says the state arrived: the pending request may be answered.
    pub(crate) fresh: bool,
    /// pending_focus is the pane this screen just asked for, by name: the
    /// owner's own `pane new` is where the owner types next, so the focus
    /// goes there as soon as the state that holds it arrives.
    pub(crate) pending_focus: Option<String>,
    /// watch says this screen watches the session and cannot change it
    /// (TODO item 60): the drawing says so, the keys change nothing, and the
    /// holder refuses a change from this connection by name.
    pub(crate) watch: bool,
}

