
use serde_json::{json, Value};

use crate::screen::{Action, Screen};

pub struct Outcome {
    pub ask: Option<Value>,
}

pub fn is_request(record: &Value) -> bool {
    matches!(
        record.get("kind").and_then(|kind| kind.as_str()),
        Some("control") | Some("view")
    )
}

pub fn request_of(record: &Value) -> (String, Vec<String>) {
    let inputs = record.get("inputs").cloned().unwrap_or(Value::Null);
    let id = inputs
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let words = inputs
        .get("words")
        .and_then(|value| value.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|one| one.as_str().map(|text| text.to_string()))
                .collect()
        })
        .unwrap_or_default();
    (id, words)
}

pub fn run(screen: &mut Screen, words: &[String]) -> Outcome {
    let said = words.join(" ");
    let action = screen.control_words(&said);
    let ask = match action {
        Action::Request(request) => Some(request),
        Action::Send(bytes) => Some(json!({
            "op": "send",
            "pane": screen.focused_pane(),
            "data": String::from_utf8_lossy(&bytes).to_string(),
        })),
        Action::Terminal(_) => {
            screen.message =
                "the Android clipboard is the owner's own terminal: a request from an agent \
                 does not write it"
                    .to_string();
            None
        }
        _ => None,
    };
    Outcome { ask }
}

pub fn answer(id: &str, data: &Value) -> Value {
    json!({
        "op": "control-result",
        "id": id,
        "data": data
    })
}
