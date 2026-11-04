use super::*;

pub(crate) fn completed(answer: &Value) -> bool {
    answer.get("state").and_then(|state| state.as_str()) == Some("completed")
}

pub(crate) fn reason(answer: &Value) -> String {
    answer
        .get("reason")
        .and_then(|reason| reason.as_str())
        .unwrap_or("the engine did not say why")
        .to_string()
}

pub(crate) fn refused(why: &str) -> Answer {
    Answer {
        ok: false,
        data: json!({ "why": why }),
        reason: why.to_string(),
    }
}

pub(crate) fn text(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(|part| part.as_str())
        .map(|found| found.to_string())
}

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

pub(crate) fn list(value: &Value, key: &str) -> Vec<Value> {
    value
        .get(key)
        .and_then(|part| part.as_array())
        .cloned()
        .unwrap_or_default()
}

