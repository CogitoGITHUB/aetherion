// One job: what an agent may do with the multiplexer — the declaration of
// the capabilities, and the work of each one over a session's wire.
//
// The declaration is DATA: the names, whether each one changes what a
// session does, and what it is for. The server checks the declaration
// against the gate before it runs anything, so a tool that lies is refused
// by name (rule 07).

use crate::wire;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

/// declaration is the capability declaration, carried inside the binary so
/// the server never looks for a file at runtime.
const DECLARATION: &str = include_str!("capabilities.json");

#[path = "tools_declare/tools_declare_capability.rs"]
mod tools_declare_capability;
pub(crate) use tools_declare_capability::*;
#[path = "tools_run/tools_run_call.rs"]
mod tools_run_call;
pub(crate) use tools_run_call::*;
#[path = "tools_session/tools_session_lookup.rs"]
mod tools_session_lookup;
pub(crate) use tools_session_lookup::*;
