// One job: the workspace seam of the holder — the engine asked, and the
// facts given back.
//
// The holder holds the session; the workspace is the one thing this
// program and the editor share. The engine owns the workspaces, their
// projects and the context, and the holder only asks the engine and gives
// the facts back. The engine's own envelope is the shape of the answer:
// the state, the data and the reason.
//
// The engine never ticks and this seam never waits: a program asks when
// it wakes on an event, and the answer comes at once.

use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};

use serde_json::{json, Value};
use workspace::Engine;

#[path = "workspace_read/workspace_read_answer.rs"]
mod workspace_read_answer;
pub(crate) use workspace_read_answer::*;
#[path = "workspace_write/workspace_write_request.rs"]
mod workspace_write_request;
pub(crate) use workspace_write_request::*;
#[path = "workspace_reply/workspace_reply_fields.rs"]
mod workspace_reply_fields;
pub(crate) use workspace_reply_fields::*;
#[cfg(test)]
#[path = "workspace_test/workspace_test_behavior.rs"]
mod tests;
