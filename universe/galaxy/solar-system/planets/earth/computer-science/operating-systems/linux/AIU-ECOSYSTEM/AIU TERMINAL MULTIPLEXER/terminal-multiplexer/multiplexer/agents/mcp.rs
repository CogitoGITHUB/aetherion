
#[path = "../holder/wire/wire_socket.rs"] mod wire;
#[path = "envelope/envelope_answer.rs"]
mod envelope;
mod tools;

use envelope::Answer;
use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::PathBuf;

const PROTOCOL_VERSION: &str = "2024-11-05";

const RULE_GATE: &str = "rule 07: read is free, a change needs the human's token";

const RULE_DECLARATION: &str =
    "rule 07: the declaration and the security predicate must agree";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let sessions_dir = match sessions_dir(&args) {
        Ok(found) => found,
        Err(why) => {
            eprintln!("mux-mcp: {}", why);
            std::process::exit(envelope::EXIT_CANNOT_RUN);
        }
    };
    std::process::exit(serve(&sessions_dir));
}

#[path = "mcp_serve/mcp_serve_loop.rs"]
mod mcp_serve_loop;
pub(crate) use mcp_serve_loop::*;
#[path = "mcp_call/mcp_call_tool.rs"]
mod mcp_call_tool;
pub(crate) use mcp_call_tool::*;
#[path = "mcp_token/mcp_token_source.rs"]
mod mcp_token_source;
pub(crate) use mcp_token_source::*;
#[path = "mcp_answer/mcp_answer_write.rs"]
mod mcp_answer_write;
pub(crate) use mcp_answer_write::*;
