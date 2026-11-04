use crate::*;

pub(crate) fn is_refusal(line: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value.get("kind").and_then(|kind| kind.as_str()) == Some("fail"),
        Err(_) => false,
    }
}

pub(crate) fn is_final(line: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value
            .get("result")
            .and_then(|result| result.get("final"))
            .and_then(|flag| flag.as_bool())
            .unwrap_or(false),
        Err(_) => false,
    }
}

