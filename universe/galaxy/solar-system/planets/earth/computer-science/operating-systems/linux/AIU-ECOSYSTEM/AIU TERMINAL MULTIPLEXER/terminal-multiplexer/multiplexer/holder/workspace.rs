
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
