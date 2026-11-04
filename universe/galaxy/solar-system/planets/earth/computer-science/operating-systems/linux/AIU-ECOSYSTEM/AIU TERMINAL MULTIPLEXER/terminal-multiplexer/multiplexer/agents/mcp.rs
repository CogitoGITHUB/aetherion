// One job: the agent's door into the multiplexer — an MCP server over stdio.
//
// The server speaks JSON-RPC 2.0 over the standard input and the standard
// output: one request per line, one answer per line. It answers with the
// one envelope, so an agent reads this server and the client the same way.
//
// Read is free: a read tool runs without a human. A change needs the human's
// token, and the server checks the token itself — the caller's word is not
// taken for what a tool does (rule 07). The declaration of the capabilities
// is data, and the server reads the gate from it before it runs anything.
//
// The exit codes are frozen: 0 when every request was answered, 2 when a
// request was refused, 3 when the server could not answer at all.

#[path = "../holder/wire.rs"] mod wire;
mod envelope;
mod tools;

use envelope::Answer;
use serde_json::{json, Value};
use std::io::{BufRead, Write};
use std::path::PathBuf;

/// protocol-version is the MCP protocol the server speaks.
const PROTOCOL_VERSION: &str = "2024-11-05";

/// rule-gate is the rule a change is gated by, named in the refusal.
const RULE_GATE: &str = "rule 07: read is free, a change needs the human's token";

/// rule-declaration is the rule a lying declaration is refused by.
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
