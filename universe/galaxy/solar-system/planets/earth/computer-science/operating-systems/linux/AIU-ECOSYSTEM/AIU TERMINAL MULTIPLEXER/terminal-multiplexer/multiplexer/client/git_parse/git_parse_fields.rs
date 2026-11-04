use super::*;

pub(crate) fn counts(status: &Value) -> String {
    let counts = status.get("counts").cloned().unwrap_or(Value::Null);
    let staged = number(&counts, "staged").unwrap_or(0);
    let unstaged = number(&counts, "unstaged").unwrap_or(0);
    let untracked = number(&counts, "untracked").unwrap_or(0);
    let conflicted = number(&counts, "conflicted").unwrap_or(0);
    format!(
        "{} staged, {} unstaged, {} untracked, {} conflicts",
        staged, unstaged, untracked, conflicted
    )
}

pub(crate) fn text(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(|part| part.as_str())
        .map(|found| found.to_string())
}

pub(crate) fn number(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|part| part.as_u64())
}

pub(crate) fn list(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .cloned()
        .unwrap_or_default()
}

