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
#[path = "pane_log/pane_log_read.rs"]
mod pane_log_read;
pub(crate) use pane_log_read::*;
#[path = "record/record_command.rs"]
mod record_command;
pub(crate) use record_command::*;
#[path = "fields/fields_request.rs"]
mod fields_request;
pub(crate) use fields_request::*;
#[path = "run/run_main.rs"]
mod run_main;
pub(crate) use run_main::*;
#[path = "pane_lookup/pane_lookup_at.rs"]
mod pane_lookup_at;
pub(crate) use pane_lookup_at::*;
#[path = "answer_control/answer_control_reply.rs"]
mod answer_control_reply;
pub(crate) use answer_control_reply::*;
#[path = "ask/ask_once.rs"]
mod ask_once;
pub(crate) use ask_once::*;
#[path = "attach/attach_client.rs"]
mod attach_client;
pub(crate) use attach_client::*;
#[path = "client_reply/client_reply_record.rs"]
mod client_reply_record;
pub(crate) use client_reply_record::*;

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

#[cfg(test)]
#[path = "holder_test/holder_test_rewind.rs"]
mod tests;
