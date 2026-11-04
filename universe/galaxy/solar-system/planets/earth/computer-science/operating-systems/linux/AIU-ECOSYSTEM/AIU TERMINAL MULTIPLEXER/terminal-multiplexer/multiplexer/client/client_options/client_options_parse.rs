use crate::*;

pub(crate) struct Options {
    pub(crate) state_dir: PathBuf,
    pub(crate) op: String,
    pub(crate) data: String,
    pub(crate) pane: String,
    pub(crate) agent_program: String,
    pub(crate) editor_program: String,
    pub(crate) editor_mcp: Vec<String>,
    pub(crate) since: u64,
    pub(crate) count: Option<u64>,
}

impl Options {
    pub(crate) fn read(args: &[String]) -> Result<Options, String> {
        let mut state_dir: Option<PathBuf> = None;
        let mut op = "state".to_string();
        let mut data = String::new();
        let mut pane = String::new();
        let mut agent_program = "opencode".to_string();
        let mut editor_program = "editor".to_string();
        let mut editor_mcp: Vec<String> = Vec::new();
        let mut since: u64 = 0;
        let mut count: Option<u64> = None;
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
                "--op" => {
                    op = value;
                    at += 2;
                }
                "--data" => {
                    data = value;
                    at += 2;
                }
                "--pane" => {
                    pane = value;
                    at += 2;
                }
                "--agent-program" => {
                    agent_program = value;
                    at += 2;
                }
                "--editor-program" => {
                    editor_program = value;
                    at += 2;
                }
                "--editor-mcp-arg" => {
                    editor_mcp.push(value);
                    at += 2;
                }
                "--since" => {
                    since = value
                        .parse()
                        .map_err(|_| "--since wants a number of records".to_string())?;
                    at += 2;
                }
                "--count" => {
                    count = Some(
                        value
                            .parse()
                            .map_err(|_| "--count wants a number of records".to_string())?,
                    );
                    at += 2;
                }
                "--help" => {
                    println!(
                        "client --state-dir DIR [--op state|attach|detach|read|send|send-agent|editor|screen|watch] [--data TEXT] [--pane NAME] [--agent-program PROGRAM] [--editor-mcp-arg WORD] [--since N] [--count N]"
                    );
                    std::process::exit(0);
                }
                other => return Err(format!("{} is not an option this client knows", other)),
            }
        }
        let state_dir = state_dir.ok_or("the client needs --state-dir")?;
        Ok(Options {
            state_dir,
            op,
            data,
            pane,
            agent_program,
            editor_program,
            editor_mcp,
            since,
            count,
        })
    }

    pub(crate) fn request(&self) -> Value {
        match self.op.as_str() {
            "attach" => json!({
                "op": "attach",
                "client": CLIENT_NAME,
                "event-contract": EVENT_CONTRACT,
                "holder-contract": HOLDER_CONTRACT
            }),
            "detach" => json!({ "op": "detach", "client": CLIENT_NAME }),
            "read" => json!({ "op": "read", "client": CLIENT_NAME, "since": self.since }),
            "send" => {
                let mut request = json!({ "op": "send", "client": CLIENT_NAME, "data": self.data });
                if !self.pane.is_empty() {
                    request["pane"] = Value::from(self.pane.clone());
                }
                request
            }
            "send-agent" => {
                let mut request = json!({
                    "op": "send-agent",
                    "client": CLIENT_NAME,
                    "selection": self.data,
                    "target": screen::agent_name(&self.agent_program),
                    "why": "the owner sent the picked text to the agents",
                });
                if !self.pane.is_empty() {
                    request["from"] = Value::from(self.pane.clone());
                }
                request
            }
            "editor" => json!({
                "op": "editor",
                "client": CLIENT_NAME,
                "command": self.editor_mcp,
                "capability": "dashboard"
            }),
            _ => json!({ "op": "state", "client": CLIENT_NAME }),
        }
    }
}
