use crate::*;

/// is_refusal answers whether a record is the holder refusing, so the client
/// can say so with its exit code.
pub(crate) fn is_refusal(line: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value.get("kind").and_then(|kind| kind.as_str()) == Some("fail"),
        Err(_) => false,
    }
}

/// is_final answers whether a record is the last one of its request: the
/// holder marks the answer, so the reader knows it is complete without
/// waiting for the connection to close.
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

