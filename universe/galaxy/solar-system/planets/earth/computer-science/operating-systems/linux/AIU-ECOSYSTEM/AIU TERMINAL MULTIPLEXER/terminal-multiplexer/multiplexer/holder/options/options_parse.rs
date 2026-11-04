use crate::*;

/// Options are the holder's arguments: the state directory is one of them, so
/// no environment variable is read for it.
pub(crate) struct Options {
    pub(crate) state_dir: PathBuf,
    /// sessions_dir is the directory this session stands in, with its siblings:
    /// the state directory's parent unless the owner names one.
    pub(crate) sessions_dir: PathBuf,
    pub(crate) shell: String,
    pub(crate) layout: Option<PathBuf>,
    pub(crate) cols: u16,
    pub(crate) rows: u16,
    /// workspace_dir is where the shared workspace engine keeps its files:
    /// it is an argument, and no environment variable names it.
    pub(crate) workspace_dir: PathBuf,
    /// workspace is the workspace this session works on, when the owner
    /// names one. Empty means the only one there is.
    pub(crate) workspace: String,
    /// log_limit is the bound the session's log keeps to, in bytes: the
    /// shipped rule unless the owner says less (TODO item 51).
    pub(crate) log_limit: u64,
}

impl Options {
    pub(crate) fn read(args: &[String]) -> Result<Options, String> {
        let mut state_dir: Option<PathBuf> = None;
        let mut shell = "/bin/sh".to_string();
        let mut layout: Option<PathBuf> = None;
        let mut cols: u16 = 80;
        let mut rows: u16 = 24;
        let mut workspace_dir: Option<PathBuf> = None;
        let mut workspace = String::new();
        let mut log_limit: u64 = log::LIMIT_BYTES;
        let mut sessions_dir: Option<PathBuf> = None;
        let mut at = 0;
        while at < args.len() {
            let name = args[at].clone();
            let value = match args.get(at + 1) {
                Some(found) => found.clone(),
                None => return Err(format!("{} needs a value", name)),
            };
            match name.as_str() {
                "--state-dir" => {
                    state_dir = Some(PathBuf::from(value));
                    at += 2;
                }
                "--shell" => {
                    shell = value;
                    at += 2;
                }
                "--layout" => {
                    layout = Some(PathBuf::from(value));
                    at += 2;
                }
                "--workspace-dir" => {
                    workspace_dir = Some(PathBuf::from(value));
                    at += 2;
                }
                "--workspace" => {
                    workspace = value;
                    at += 2;
                }
                "--cols" => {
                    cols = value
                        .parse()
                        .map_err(|_| "--cols wants a number of columns".to_string())?;
                    at += 2;
                }
                "--sessions-dir" => {
                    sessions_dir = Some(PathBuf::from(value));
                    at += 2;
                }
                "--log-limit" => {
                    log_limit = value
                        .parse()
                        .map_err(|_| "--log-limit wants a number of bytes".to_string())?;
                    at += 2;
                }
                "--rows" => {
                    rows = value
                        .parse()
                        .map_err(|_| "--rows wants a number of rows".to_string())?;
                    at += 2;
                }
                "--help" => {
                    println!(
                        "holder --state-dir DIR [--shell PROGRAM] [--layout FILE] \
                         [--cols N] [--rows N] [--log-limit BYTES] \
                         [--workspace-dir DIR] [--workspace NAME]"
                    );
                    std::process::exit(0);
                }
                other => return Err(format!("{} is not an option this holder knows", other)),
            }
        }
        let state_dir = state_dir.ok_or("the holder needs --state-dir")?;
        let workspace_dir = workspace_dir.unwrap_or_else(|| state_dir.join("workspace"));
        let sessions_dir = sessions_dir.unwrap_or_else(|| sessions::dir_of(&state_dir));
        Ok(Options {
            state_dir,
            sessions_dir,
            shell,
            layout,
            cols,
            rows,
            workspace_dir,
            workspace,
            log_limit,
        })
    }
}

