use super::*;

pub fn run(cap: &Capability, arguments: &Value, sessions_dir: &Path) -> Result<Value, String> {
    match cap.name.as_str() {
        "multiplexer_sessions" => sessions(sessions_dir),
        "multiplexer_records" => {
            let session = named_session(arguments, sessions_dir)?;
            let since = arguments.get("since").and_then(|v| v.as_u64()).unwrap_or(0);
            let mut request = json!({ "op": "read", "client": "mux-mcp/1", "since": since });
            if let Some(text) = arguments.get("data").and_then(|v| v.as_str()) {
                request["data"] = Value::from(text);
            }
            let held = ask_holder(&session, request)?;
            Ok(json!({ "session": session_name(arguments), "records": held }))
        }
        "multiplexer_send" => {
            let session = named_session(arguments, sessions_dir)?;
            let data = arguments
                .get("data")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let request = json!({ "op": "send", "client": "mux-mcp/1", "data": data });
            let mut request = request;
            if let Some(pane) = arguments.get("pane").and_then(|v| v.as_str()) {
                request["pane"] = Value::from(pane);
            }
            let held = ask_holder(&session, request)?;
            Ok(json!({ "session": session_name(arguments), "records": held }))
        }
        "multiplexer_control" => {
            let session = named_session(arguments, sessions_dir)?;
            let words: Vec<String> = arguments
                .get("words")
                .and_then(|value| value.as_array())
                .map(|list| {
                    list.iter()
                        .filter_map(|one| one.as_str().map(|text| text.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            if words.is_empty() {
                return Err("a control needs the words of the command".to_string());
            }
            let mut request = json!({
                "op": "control",
                "client": "mux-mcp/1",
                "id": next_id(),
                "words": words
            });
            if let Some(token) = arguments.get("confirm").and_then(|value| value.as_str()) {
                request["confirm"] = Value::from(token);
            }
            let held = ask_holder(&session, request)?;
            Ok(answered(session_name(arguments), held))
        }
        "multiplexer_view" => {
            let session = named_session(arguments, sessions_dir)?;
            let request = json!({
                "op": "view",
                "client": "mux-mcp/1",
                "id": next_id()
            });
            let held = ask_holder(&session, request)?;
            Ok(answered(session_name(arguments), held))
        }
        other => Err(format!("there is no tool named {}", other)),
    }
}

pub(crate) fn answered(session: String, held: Vec<Value>) -> Value {
    let mut said = json!({ "session": session, "records": held });
    if let Some(last) = held.last() {
        if let Some(data) = last
            .get("outputs")
            .and_then(|outputs| outputs.get("data"))
        {
            said["data"] = data.clone();
        }
    }
    said
}

pub(crate) fn next_id() -> String {
    static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    let count = COUNTER.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    format!("c-{}-{}", std::process::id(), count)
}

