// One job: the client — a thin screen that attaches to a holder, asks it
// things, and lets go again.
//
// The client holds nothing: the shell and the log belong to the holder, so a
// client that ends takes nothing with it (rule 01). It reads no environment
// variable for the session: the state directory is an argument.
//
// Its wait for the holder's socket ends on the filesystem event that creates
// it, never on a clock.

#[path = "../holder/wire.rs"] mod wire;
#[path = "../holder/geometry.rs"] mod geometry;
#[allow(dead_code)]
#[path = "../tty/tty.rs"] mod tty;

// The work mode's config: the devloop area sits below the client, so this is a
// downward edge and the only one the client takes.
#[path = "../devloop/config.rs"]
mod config;

mod clipboard;
mod git;
mod workspace;
mod editor;
mod keymap;
mod screen;
mod select;
mod control;

use serde_json::{json, Value};
use std::path::{Path, PathBuf};

const EVENT_CONTRACT: &str = "event-log-format/1";
const HOLDER_CONTRACT: &str = "multiplexer-holder/1";
const CLIENT_NAME: &str = "multiplexer-client/1";

/// BUILD is the build this client is: the crate's own version, printed when it
/// starts, so a rebuilt client that meets an older holder can say what it is
/// (TODO item 48).
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

