use super::*;

/// completed answers whether the engine's answer says the work was done.
pub(crate) fn completed(answer: &Value) -> bool {
    answer.get("state").and_then(|state| state.as_str()) == Some("completed")
}

/// reason answers why the engine refused, in its own words.
pub(crate) fn reason(answer: &Value) -> String {
    answer
        .get("reason")
        .and_then(|reason| reason.as_str())
        .unwrap_or("the engine did not say why")
        .to_string()
}

/// refused answers a seam that could not ask: the reason, and no data.
pub(crate) fn refused(why: &str) -> Answer {
    Answer {
        ok: false,
        data: json!({ "why": why }),
        reason: why.to_string(),
    }
}

/// text answers one string field of a value.
pub(crate) fn text(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(|part| part.as_str())
        .map(|found| found.to_string())
}

/// strings answers the list of strings under a key of a value.
pub(crate) fn strings(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .map(|found| {
            found
                .iter()
                .filter_map(|part| part.as_str())
                .map(|part| part.to_string())
                .collect()
        })
        .unwrap_or_default()
}

/// list answers the list under a key of a value.
pub(crate) fn list(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .cloned()
        .unwrap_or_default()
}

