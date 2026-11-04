use crate::*;

/// Client is one connection to the socket: its descriptor, the bytes that
/// arrived but do not yet make a whole request, and whether it is attached.
pub(crate) struct Client {
    pub(crate) fd: c_int,
    pub(crate) pending: String,
    pub(crate) attached: bool,
    pub(crate) dead: bool,
    /// role says what this client is: the screen is the owner's own view of
    /// the session, and the agent's words run there. A client with no role
    /// is a reader.
    pub(crate) role: String,
}

/// Pending is one agent's request that waits for the screen's answer: the
/// id of the request and the descriptor of the client that asked.
pub(crate) struct Pending {
    pub(crate) id: String,
    pub(crate) requester_fd: c_int,
}

/// Session is one held session: its panes, its log, its socket and its
/// clients.
pub(crate) struct Session {
    pub(crate) run_id: String,
    pub(crate) state_dir: PathBuf,
    /// sessions_dir is where this session stands with its siblings, so a client
    /// can name another one (TODO item 49).
    pub(crate) sessions_dir: PathBuf,
    /// workspace_dir is where the shared workspace engine keeps its files.
    pub(crate) workspace_dir: PathBuf,
    /// workspace is the workspace this session works on, when the owner
    /// names one.
    pub(crate) workspace: String,
    pub(crate) log_path: PathBuf,
    pub(crate) socket_path: PathBuf,
    pub(crate) log: log::Log,
    pub(crate) panes: Vec<Pane>,
    pub(crate) tabs: Vec<String>,
    pub(crate) direction: String,
    pub(crate) cols: u16,
    pub(crate) rows: u16,
    /// area_rows are the rows the panes get: the window minus the screen's
    /// own furniture. The client says how many it draws with.
    pub(crate) area_rows: u16,
    /// layout_path is the file the layout was read from: the session's
    /// shape is written back where it was read.
    pub(crate) layout_path: Option<PathBuf>,
    pub(crate) seq: u64,
    pub(crate) started: Instant,
    pub(crate) listen_fd: c_int,
    pub(crate) clients: Vec<Client>,
    /// pending are the agent's requests that wait for the screen's answer.
    pub(crate) pending: Vec<Pending>,
}

/// Pane is one pane of the session: a name and the shell it holds. The name
/// is how everything else talks about the pane.
pub(crate) struct Pane {
    pub(crate) name: String,
    pub(crate) tab: String,
    pub(crate) weight: u16,
    /// args are the arguments the program was started with: a restarted pane
    /// runs the same program the same way.
    #[allow(dead_code)]
    pub(crate) args: Vec<String>,
    /// hidden says the pane is closed and not drawn, and its shell keeps
    /// running: a close hides, and a kill is another word (TODO item 45).
    pub(crate) hidden: bool,
    /// typed is what the owner has typed into this pane since the last
    /// newline: the command the pane is given is the line that ends here.
    pub(crate) typed: String,
    pub(crate) shell: shells::Shell,
}

