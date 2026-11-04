
#[path = "../holder/wire/wire_socket.rs"] mod wire;
#[path = "../holder/geometry/geometry_rects.rs"] mod geometry;
#[allow(dead_code)]
#[path = "../tty/terminal/terminal_raw.rs"] mod tty;

#[path = "../devloop/config.rs"]
mod config;

#[path = "clipboard/clipboard_osc.rs"]
mod clipboard;
mod git;
#[path = "workspace/workspace_lines.rs"]
mod workspace;
#[path = "editor/editor_lines.rs"]
mod editor;
mod keymap;
mod screen;
#[path = "select/select_region.rs"]
mod select;
#[path = "control/control_request.rs"]
mod control;

use serde_json::{json, Value};
use std::path::{Path, PathBuf};

const EVENT_CONTRACT: &str = "event-log-format/1";
const HOLDER_CONTRACT: &str = "multiplexer-holder/1";
const CLIENT_NAME: &str = "multiplexer-client/1";

const BUILD: &str = env!("CARGO_PKG_VERSION");

#[path = "client_run/client_run_screen.rs"]
mod client_run_screen;
pub(crate) use client_run_screen::*;
#[path = "client_run/client_run_request.rs"]
mod client_run_request;
pub(crate) use client_run_request::*;
#[path = "client_reply/client_reply_kind.rs"]
mod client_reply_kind;
pub(crate) use client_reply_kind::*;
#[path = "client_options/client_options_parse.rs"]
mod client_options_parse;
pub(crate) use client_options_parse::*;
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => std::process::exit(code),
        Err(why) => {
            eprintln!("client: {}", why);
            std::process::exit(1);
        }
    }
}

