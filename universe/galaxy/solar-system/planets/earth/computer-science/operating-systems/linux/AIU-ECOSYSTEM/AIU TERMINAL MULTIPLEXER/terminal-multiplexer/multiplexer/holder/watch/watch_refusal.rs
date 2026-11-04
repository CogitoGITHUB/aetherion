// One job: what a watcher may ask of the session — the read-only rule as one
// total predicate, so the holder refuses by name in one place.
//
// A watcher attaches to see the records and the drawing (TODO item 60). It is
// not the owner's screen: it can watch what the session does and cannot change
// it. The rule is a list of the ops that change something; every other op
// reads, and a read is free (rule 07).
//
// The list is here and nowhere else: the holder asks this predicate before it
// dispatches a watcher's request, so a new op that changes something is added
// here once and cannot slip through a second dispatch path.

use serde_json::Value;

/// the_ops_that_change is every op whose work is a change to the session:
/// what a watcher may not run. It is data, and the test below keeps it honest.
pub const THE_OPS_THAT_CHANGE: &[&str] = &[
    "send",
    "send-agent",
    "control",
    "open",
    "close",
    "rename",
    "resize",
    "weight",
    "kill",
    "shutdown",
];

/// refusal answers why a watcher's request is refused, and None when the
/// request only reads. The answer names the op, so the owner reads what was
/// asked and not only that something was.
pub fn refusal(request: &Value) -> Option<String> {
    let op = request
        .get("op")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if THE_OPS_THAT_CHANGE.contains(&op.as_str()) {
        return Some(format!(
            "a watcher may not run {}: this client watches the session and cannot change it",
            op
        ));
    }
    // The session command reads with `show` and changes with the rest: a
    // watcher may look at a pane and may not create, rename or kill a session.
    if op == "session" {
        let what = request
            .get("what")
            .and_then(|value| value.as_str())
            .unwrap_or("");
        if what != "show" {
            return Some(format!(
                "a watcher may not run session {}: this client watches and cannot change it",
                if what.is_empty() { "with no what" } else { what }
            ));
        }
    }
    None
}

#[cfg(test)]
#[path = "watch_test/watch_test_behavior.rs"]
mod tests;
