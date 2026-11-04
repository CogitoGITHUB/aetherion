
use serde_json::Value;

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
