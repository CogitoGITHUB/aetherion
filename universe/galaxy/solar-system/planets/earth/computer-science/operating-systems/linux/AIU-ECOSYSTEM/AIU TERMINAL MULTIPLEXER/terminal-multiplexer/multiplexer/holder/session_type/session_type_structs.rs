use crate::*;

pub(crate) struct Client {
    pub(crate) fd: c_int,
    pub(crate) pending: String,
    pub(crate) attached: bool,
    pub(crate) dead: bool,
    pub(crate) role: String,
}

pub(crate) struct Pending {
    pub(crate) id: String,
    pub(crate) requester_fd: c_int,
}

pub(crate) struct Session {
    pub(crate) run_id: String,
    pub(crate) state_dir: PathBuf,
    pub(crate) sessions_dir: PathBuf,
    pub(crate) workspace_dir: PathBuf,
    pub(crate) workspace: String,
    pub(crate) log_path: PathBuf,
    pub(crate) socket_path: PathBuf,
    pub(crate) log: log::Log,
    pub(crate) panes: Vec<Pane>,
    pub(crate) tabs: Vec<String>,
    pub(crate) direction: String,
    pub(crate) cols: u16,
    pub(crate) rows: u16,
    pub(crate) area_rows: u16,
    pub(crate) layout_path: Option<PathBuf>,
    pub(crate) seq: u64,
    pub(crate) started: Instant,
    pub(crate) listen_fd: c_int,
    pub(crate) clients: Vec<Client>,
    pub(crate) pending: Vec<Pending>,
}

pub(crate) struct Pane {
    pub(crate) name: String,
    pub(crate) tab: String,
    pub(crate) weight: u16,
    #[allow(dead_code)]
    pub(crate) args: Vec<String>,
    pub(crate) hidden: bool,
    pub(crate) typed: String,
    pub(crate) shell: shells::Shell,
}

