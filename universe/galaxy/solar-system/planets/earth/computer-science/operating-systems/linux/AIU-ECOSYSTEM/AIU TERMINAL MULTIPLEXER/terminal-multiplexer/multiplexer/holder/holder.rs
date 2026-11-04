// One job: the session — the holder that outlives every client, keeps the
// shell alive, and serves the socket.
//
// No config and no timers (rule 03): the state directory is an argument and
// no environment variable is read for it, no clock is started, and nothing is
// polled in a loop. Every wait ends on an event — the shell wrote, the shell
// exited, a client asked, the socket closed — through one poll that waits for
// exactly those events and nothing else.
//
// The wire is one JSON object per line (rule 07), in the ecosystem's event
// shape: the client says attach, detach, read, state or send; the holder
// answers with records and never dies because a client went.

#[path = "../tty/facade.rs"] mod facade;
#[path = "../tty/measure.rs"] mod measure;
#[path = "../tty/tty.rs"] mod tty;
mod editor;
mod git;
mod geometry;
mod layout;
mod log;
mod sessions;
mod watch;
mod workspace;

#[path = "../agents/bundle.rs"]
mod bundle;
mod shells;
#[path = "request_client/request_client_detach.rs"]
mod request_client_detach;
#[path = "request_view/request_view_state.rs"]
mod request_view_state;
#[path = "request_view/request_view_git.rs"]
mod request_view_git;
#[path = "request_view/request_view_workspace.rs"]
mod request_view_workspace;
#[path = "request_view/request_view_editor.rs"]
mod request_view_editor;
#[path = "request_view/request_view_read.rs"]
mod request_view_read;
#[path = "request_send/request_send_text.rs"]
mod request_send_text;
#[path = "request_send/request_send_agent.rs"]
mod request_send_agent;
#[path = "request_pane/request_pane_open.rs"]
mod request_pane_open;
#[path = "request_pane/request_pane_resize.rs"]
mod request_pane_resize;
#[path = "request_pane/request_pane_weight.rs"]
mod request_pane_weight;
#[path = "request_pane/request_pane_rename.rs"]
mod request_pane_rename;
#[path = "request_pane/request_pane_close.rs"]
mod request_pane_close;
#[path = "session_type/session_type_structs.rs"]
mod session_type_structs;
pub(crate) use session_type_structs::*;
#[path = "session_type/session_type_methods.rs"]
mod session_type_methods;
pub(crate) use session_type_methods::*;
#[path = "serve/serve_loop.rs"]
mod serve_loop;
pub(crate) use serve_loop::*;
#[path = "serve/serve_read.rs"]
mod serve_read;
pub(crate) use serve_read::*;
#[path = "handler_session/handler_session_lifecycle.rs"]
mod handler_session_lifecycle;
pub(crate) use handler_session_lifecycle::*;
#[path = "handler_pane/handler_pane_inspect.rs"]
mod handler_pane_inspect;
pub(crate) use handler_pane_inspect::*;
#[path = "ask/ask_screen_control.rs"]
mod ask_screen_control;
pub(crate) use ask_screen_control::*;
#[path = "options/options_parse.rs"]
mod options_parse;
pub(crate) use options_parse::*;
#[path = "socket/socket_link.rs"]
mod socket_link;
pub(crate) use socket_link::*;

use libc::c_int;
use serde_json::{json, Value};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::time::Instant;

const EVENT_CONTRACT: &str = "event-log-format/1";
const HOLDER_CONTRACT: &str = "multiplexer-holder/1";

/// AGENT_PANES are the panes a bundle goes to: the multiplexer's own agent
/// and the editor's agent. Both run the same agent program, so one bundle
/// serves both, and a pane with another name is not an agent.
const AGENT_PANES: [&str; 2] = ["agent", "editor-agent"];

/// pane_log_tail answers the last words one pane's program said, as the
/// session's log holds them. It reads the log and never the drawing.
fn pane_log_tail(session: &Session, pane: &str, limit: usize) -> String {
    let held = match log::Log::records(&session.log_path) {
        Ok(held) => held,
        Err(_) => return String::new(),
    };
    let mut lines: Vec<String> = Vec::new();
    for record in held.iter().rev().take(limit).rev() {
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            lines.push(text.to_string());
        }
    }
    lines.join("\n")
}

/// REWIND_LINES is how many of a pane's lines a rewind shows: the newest ones
/// up to the record the owner chose, so the view is a page and not a flood.
const REWIND_LINES: usize = 200;

/// pane_text_at answers the lines one pane had said by one record, read from
/// the log: every record of that pane up to and including the seq, and never
/// one after it. The newest REWIND_LINES of them are the answer, so a long
/// session still reads as a page.
///
/// This is a read of the journal and nothing else: it changes no pane and
/// writes no record, so looking back cannot change what the pane is doing.
fn pane_text_at(held: &[Value], pane: &str, until: u64, limit: usize) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for record in held {
        let seq = record.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
        if seq > until {
            break;
        }
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            lines.push(text.to_string());
        }
    }
    let from = lines.len().saturating_sub(limit);
    lines.drain(0..from);
    lines
}

/// command_record answers the command one pane was given and what that pane
/// printed after it: the two parts of one record, read from the log. A pane
/// with no command yet answers nothing, and the bundle carries neither part.
fn command_record(session: &Session, pane: &str) -> (String, String) {
    if pane.is_empty() {
        return (String::new(), String::new());
    }
    let held = match log::Log::records(&session.log_path) {
        Ok(held) => held,
        Err(_) => return (String::new(), String::new()),
    };
    let mut command = String::new();
    let mut at = 0;
    for (number, record) in held.iter().enumerate() {
        let of_pane = record
            .get("inputs")
            .and_then(|inputs| inputs.get("pane"))
            .and_then(|value| value.as_str());
        let is_command = record.get("kind").and_then(|value| value.as_str()) == Some("command");
        if is_command && of_pane == Some(pane) {
            command = record
                .get("inputs")
                .and_then(|inputs| inputs.get("command"))
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            at = number + 1;
        }
    }
    if command.is_empty() {
        return (String::new(), String::new());
    }
    let mut said: Vec<String> = Vec::new();
    for record in held.iter().skip(at) {
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            said.push(text.to_string());
        }
    }
    (command, said.join("\n"))
}

/// Fields are the story of one record: what happened, who did it, why, and
/// how. The identity and timing fields are added by the session itself.
struct Fields<'a> {
    kind: &'a str,
    who: &'a str,
    what: &'a str,
    why: &'a str,
    how: &'a str,
    inputs: Value,
    outputs: Value,
    result: Value,
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => {}
        Err(why) => {
            eprintln!("holder: {}", why);
            std::process::exit(1);
        }
    }
}

/// run holds one session from the first moment to the last.
fn run(args: &[String]) -> Result<(), String> {
    let options = Options::read(args)?;
    // The holder says which build it is: a client that meets it at attach
    // compares the contracts, and the refusal must be able to name both sides.
    eprintln!(
        "holder: build {} — contracts {} and {}",
        env!("CARGO_PKG_VERSION"),
        HOLDER_CONTRACT,
        EVENT_CONTRACT
    );
    // The state directory is the owner's alone (TODO item 51): 0700, and the
    // files the session writes in it are 0600.
    log::private_dir(&options.state_dir)?;

    let log_path = options.state_dir.join("events.log");
    let socket_path = options.state_dir.join("holder.sock");
    let pid_path = options.state_dir.join("holder.pid");

    if socket_path.exists() {
        // A connection is not proof: this phone answers connect() on a socket
        // a dead holder left behind, and then says nothing. The proof is an
        // answer, so the question is asked before the session is called held.
        let stale = match connect(&socket_path) {
            Ok(fd) => {
                let answers = answers_holder(fd);
                close(fd);
                !answers
            }
            Err(_) => true,
        };
        if !stale {
            return Err(format!(
                "a holder already holds the session in {}",
                options.state_dir.display()
            ));
        }
        std::fs::remove_file(&socket_path).map_err(|why| {
            format!(
                "the stale socket {} cannot be removed: {}",
                socket_path.display(),
                why
            )
        })?;
    }

    let log = log::Log::open_with(&log_path, options.log_limit, log::KEEP_RECORDS)?;
    let listen_fd = bind(&socket_path)?;

    // The panes of the session: the layout file names them, or the smallest
    // layout there is holds one pane with one shell.
    let wanted = match &options.layout {
        Some(path) => layout::read(path)?,
        None => layout::one("main", &options.shell, options.cols, options.rows),
    };
    let direction = wanted.direction.clone();
    let mut panes: Vec<Pane> = Vec::new();
    let mut tabs: Vec<String> = Vec::new();
    for pane in wanted.panes {
        let shell = shells::Shell::start(&pane.program, &[], pane.cols, pane.rows)?;
        if !tabs.contains(&pane.tab) {
            tabs.push(pane.tab.clone());
        }
        panes.push(Pane {
            name: pane.name,
            tab: pane.tab,
            weight: pane.weight,
            hidden: false,
            args: Vec::new(),
            typed: String::new(),
            shell,
        });
    }

    let run_id = format!("mux-{}-{}", options.shell.replace('/', "-"), std::process::id());
    let mut session = Session {
        run_id,
        state_dir: options.state_dir.clone(),
        sessions_dir: options.sessions_dir.clone(),
        workspace_dir: options.workspace_dir.clone(),
        workspace: options.workspace.clone(),
        log_path,
        socket_path,
        log,
        panes,
        tabs,
        direction,
        cols: options.cols,
        rows: options.rows,
        area_rows: options.rows,
        layout_path: options.layout.clone(),
        seq: 0,
        started: Instant::now(),
        listen_fd,
        clients: Vec::new(),
        pending: Vec::new(),
    };

    std::fs::write(&pid_path, format!("{}", std::process::id())).map_err(|why| {
        format!(
            "the holder's pid cannot be written to {}: {}",
            pid_path.display(),
            why
        )
    })?;
    log::private_file(&pid_path)?;

    let mut measured: serde_json::Map<String, Value> = serde_json::Map::new();
    for (key, value) in measure::record(&session.panes[0].shell.measured) {
        measured.insert(key.to_string(), value);
    }
    let start = session.record(Fields {
        kind: "start",
        who: "holder",
        what: "the session holds its panes",
        why: "the holder was asked to hold a session",
        how: "a pty was opened for every pane, the shell was started on it, the socket was bound",
        inputs: json!({
            "state-dir": options.state_dir.display().to_string(),
            "layout": match &options.layout {
                Some(path) => path.display().to_string(),
                None => "one pane".to_string(),
            },
            "panes": session.panes.iter().map(|pane| pane.name.clone()).collect::<Vec<String>>()
        }),
        outputs: json!({
            "session": session.run_id.clone(),
            "socket": session.socket_path.display().to_string(),
            "log": session.log_path.display().to_string(),
            "measured": Value::Object(measured)
        }),
        result: json!({}),
    });
    session.write(&start);

    serve(&mut session)
}

/// pane_at answers the pane of that name, or the first pane when the name is
/// empty: the session's panes are addressed by name.
fn pane_at(session: &Session, name: &str) -> Result<usize, String> {
    if name.is_empty() {
        return Ok(0);
    }
    session
        .panes
        .iter()
        .position(|pane| pane.name == name)
        .ok_or_else(|| format!("there is no pane named {}", name))
}

/// answer handles one request line and answers it on the same wire.
fn answer(session: &mut Session, at: usize, line: &str) -> Result<bool, String> {
    let request: Value = match serde_json::from_str(line) {
        Ok(value) => value,
        Err(why) => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the request is not a record",
                why: "the line on the wire is not one JSON object",
                how: "the line was parsed and refused",
                inputs: json!({ "line": line }),
                outputs: json!({}),
                result: json!({ "why": why.to_string() }),
            });
            answer_client(session, at, &record);
            return Ok(false);
        }
    };
    let op = request
        .get("op")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();

    // A watcher sees the session and never changes it (TODO item 60). The
    // rule is one predicate over the op, and the refusal names both the op
    // and the rule: a watcher that asks for a change is refused here, before
    // the dispatch, so no op can reach a change by a second path.
    if session.clients[at].role == "watch" {
        if let Some(why) = watch::refusal(&request) {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "a watcher's request was refused",
                why: &why,
                how: "the client attached as a watcher, so its op was compared with the \
                      ops that change the session",
                inputs: json!({ "op": op, "client": client_name(&request) }),
                outputs: json!({}),
                result: json!({
                    "rule": "a watcher sees the records and the drawing; it cannot change \
                             the session"
                }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(true);
        }
    }

    match op.as_str() {
        "attach" => attach(session, at, &request),
        "detach" => request_client_detach::request_client_detach(session, at, &request),
        "state" => request_view_state::request_view_state(session, at, &request),
        "git" => request_view_git::request_view_git(session, at, &request),
        "workspace" => request_view_workspace::request_view_workspace(session, at, &request),
        "editor" => request_view_editor::request_view_editor(session, at, &request),
        "rewind" => rewind(session, at, &request),
        "sessions" => list_sessions(session, at),
        "session" => session_command(session, at, &request),
        "shutdown" => shutdown(session, at),
        "control" => control(session, at, &request),
        "view" => view(session, at, &request),
        "control-result" => control_result(session, at, &request),
        "read" => request_view_read::request_view_read(session, at, &request),
        "send" => request_send_text::request_send_text(session, at, &request),
        "send-agent" => request_send_agent::request_send_agent(session, at, &request),
        "kill" => kill_pane(session, at, &request),
        "open" => request_pane_open::request_pane_open(session, at, &request),
        "resize" => request_pane_resize::request_pane_resize(session, at, &request),
        "weight" => request_pane_weight::request_pane_weight(session, at, &request),
        "rename" => request_pane_rename::request_pane_rename(session, at, &request),
        "close" => request_pane_close::request_pane_close(session, at, &request),

        other => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the request is not one this holder knows",
                why: "the op on the wire is not in the set",
                how: "the op was read and refused by name",
                inputs: json!({ "op": other }),
                outputs: json!({}),
                result: json!({
                    "ops": [
                        "attach",
                        "detach",
                        "read",
                        "state",
                        "send",
                        "open",
                        "control",
                        "view",
                        "control-result"
                    ]
                }),
            });
            answer_client(session, at, &record);
            Ok(false)
        }
    }
}

/// control is the agent's door into the screen: the words the agent sent,
/// and the screen's answer. A change needs the human's token, and the holder
/// checks it itself (rule 07): the caller's word is not taken for what it
/// does.
///
/// The holder holds no screen of its own. The words run on the owner's own
/// screen, so the agent and the owner drive the same code.
fn control(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let words: Vec<String> = request
        .get("words")
        .and_then(|value| value.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|one| one.as_str().map(|text| text.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let given = request
        .get("confirm")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if !session.token_matches(&given) {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the agent's change was refused",
            why: "a change needs the human's token, and it was refused",
            how: "the token was compared with the session's own token",
            inputs: json!({ "id": id, "words": words }),
            outputs: json!({}),
            result: json!({
                "rule": "rule 07: read is free, a change needs the human's token"
            }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    ask_screen(session, at, &id, &words, "control")
}

/// view is the agent's read of the screen: what the owner sees. A read is
/// free, so it needs no token.
fn view(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    ask_screen(session, at, &id, &[], "view")
}

/// list_sessions answers what stands in the sessions directory: every session,
/// and whether a holder holds it. It is a read: nothing is made or ended.
fn list_sessions(session: &mut Session, at: usize) -> Result<bool, String> {
    let list = sessions::listing(&session.sessions_dir);
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the sessions were listed",
        why: "the owner asked what stands",
        how: "the sessions directory was read and every session's socket was tried",
        inputs: json!({ "sessions-dir": session.sessions_dir.to_string_lossy() }),
        outputs: list,
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

/// a_fail answers one refusal to the client that asked, and says the rule that
/// refused: every one of the four session commands answers by name.
fn a_fail(session: &mut Session, at: usize, what: &str, why: String, inputs: Value) {
    let record = session.record(Fields {
        kind: "fail",
        who: "holder",
        what: what,
        why: &why,
        how: "the word was read, checked, and refused by name",
        inputs,
        outputs: json!({}),
        result: json!({ "why": why }),
    });
    session.write(&record);
    answer_client(session, at, &record);
}

/// session_command runs one of the owner's four session commands: create,
/// rename, kill. The fourth, the listing, is list_sessions above.
fn session_command(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let what = request
        .get("what")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if let Err(why) = sessions::check_name(&name) {
        a_fail(session, at, "the session command was refused", why,
            json!({ "what": what, "name": name }));
        return Ok(true);
    }
    match what.as_str() {
        "create" => create_session(session, at, &name),
        "rename" => rename_session(session, at, &name),
        "kill" => kill_session(session, at, &name),
        "show" => show_pane(session, at, &name),
        other => {
            a_fail(session, at, "the session command was refused",
                format!("{} is not one of create, rename, kill or show", other),
                json!({ "what": other, "name": name }));
            Ok(true)
        }
    }
}

/// ask_once connects to another session's socket, sends one request, and
/// answers the one line that comes back. It is a single exchange: no clock and
/// no retry, so a session that does not answer is a session that was not
/// touched.
fn ask_once(socket: &Path, request: &Value) -> Result<Value, String> {
    let fd = connect(socket)?;
    let mut line = request.to_string();
    line.push('\n');
    write_to(fd, line.as_bytes())?;
    let mut answer = String::new();
    while !answer.contains('\n') {
        let mut buffer = [0u8; 4096];
        let got = facade::read_bytes(fd, &mut buffer)?;
        if got == 0 {
            break;
        }
        answer.push_str(&String::from_utf8_lossy(&buffer[..got]));
    }
    close(fd);
    let first = answer.lines().next().unwrap_or("").to_string();
    serde_json::from_str(&first)
        .map_err(|why| format!("the answer is not a record: {}", why))
}

/// attach answers a client that wants to watch the session. The contracts are
/// exchanged before anything else, and a mismatch refuses by name.
fn attach(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let client_event = request
        .get("event-contract")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    let client_holder = request
        .get("holder-contract")
        .and_then(|value| value.as_str())
        .unwrap_or("");

    if client_event != EVENT_CONTRACT || client_holder != HOLDER_CONTRACT {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the client and the holder do not agree on the contract",
            why: "the versions exchanged at attach differ",
            how: "the two versions were compared and the attach was refused by name",
            inputs: json!({
                "client-event-contract": client_event,
                "client-holder-contract": client_holder
            }),
            outputs: json!({
                "holder-event-contract": EVENT_CONTRACT,
                "holder-holder-contract": HOLDER_CONTRACT
            }),
            result: json!({
                "safe-path": "finish the session and restart the holder, or run the old client"
            }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(false);
    }

    session.clients[at].attached = true;
    // The screen says what it is: the agent's words run on the owner's own
    // screen, and nowhere else.
    let role = request
        .get("role")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    session.clients[at].role = role;
    let record = session.state("the client attached and the contracts agree");
    session.write(&record);
    // The answer is not the last one: the client stays and watches what the
    // session says next.
    answer_client_more(session, at, &record);
    Ok(true)
}

/// client_name answers the name a client gave, or a plain one.
fn client_name(request: &Value) -> String {
    request
        .get("client")
        .and_then(|value| value.as_str())
        .unwrap_or("a client")
        .to_string()
}

/// answer_client puts one record on one client's wire and says so when it
/// cannot: a client that gets no answer must hear why.
///
/// The answer is marked as the last one of that request, so a reader knows
/// when the answer is complete without waiting for the connection to close.
fn answer_client(session: &mut Session, at: usize, record: &Value) {
    let fd = session.clients[at].fd;
    let mut answer = record.clone();
    if let Some(result) = answer.get_mut("result").and_then(|value| value.as_object_mut()) {
        result.insert("final".to_string(), Value::Bool(true));
    }
    if let Err(why) = write_to(fd, record_line(&answer).as_bytes()) {
        eprintln!("holder: the client on fd {} was not answered: {}", fd, why);
    }
}

/// answer_client_more puts one record on a client's wire without marking it
/// as the last one: the client stays and watches what comes next.
fn answer_client_more(session: &mut Session, at: usize, record: &Value) {
    let fd = session.clients[at].fd;
    if let Err(why) = write_to(fd, record_line(record).as_bytes()) {
        eprintln!("holder: the client on fd {} was not answered: {}", fd, why);
    }
}

/// record_line answers one record as it goes on the wire: one JSON object,
/// one line. The newline is what makes a line a line for the reader on the
/// other end.
fn record_line(record: &Value) -> String {
    let mut text = record.to_string();
    text.push('\n');
    text
}

/// close closes one descriptor and says nothing.
fn close(fd: c_int) {
    if fd >= 0 {
        unsafe {
            libc::close(fd);
        }
    }
}

/// utc_now answers the wall clock as a person reads it, without a date
/// library: the kernel holds the broken-down time and this formats it.
fn utc_now() -> String {
    let now = unsafe { libc::time(std::ptr::null_mut()) };
    let mut parts: libc::tm = unsafe { std::mem::zeroed() };
    unsafe {
        libc::gmtime_r(&now, &mut parts);
    }
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        parts.tm_year + 1900,
        parts.tm_mon + 1,
        parts.tm_mday,
        parts.tm_hour,
        parts.tm_min,
        parts.tm_sec
    )
}

#[cfg(test)]
#[path = "holder_test/holder_test_rewind.rs"]
mod tests;
