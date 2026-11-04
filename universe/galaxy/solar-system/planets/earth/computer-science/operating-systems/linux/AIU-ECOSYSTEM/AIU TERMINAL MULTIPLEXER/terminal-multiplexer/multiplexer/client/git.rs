// One job: the Git panel — the shared model as the multiplexer shows it.
//
// The panel is built from the data the holder answers with: the shared
// layer's own model, read as the multiplexer reads it. The marks are the
// layer's marks, so the two programs say the same thing about the same
// repository.
//
// Nothing here runs Git and nothing here decides anything: the holder
// asked the layer, and this file only turns the answer into lines.

use serde_json::Value;

#[path = "git_view/git_view_overview.rs"]
mod git_view_overview;
pub(crate) use git_view_overview::*;
#[path = "git_view/git_view_worktrees.rs"]
mod git_view_worktrees;
pub(crate) use git_view_worktrees::*;
#[path = "git_view/git_view_history.rs"]
mod git_view_history;
pub(crate) use git_view_history::*;
#[path = "git_parse/git_parse_fields.rs"]
mod git_parse_fields;
pub(crate) use git_parse_fields::*;
#[cfg(test)]
#[path = "git_test/git_test_behavior.rs"]
mod tests;
