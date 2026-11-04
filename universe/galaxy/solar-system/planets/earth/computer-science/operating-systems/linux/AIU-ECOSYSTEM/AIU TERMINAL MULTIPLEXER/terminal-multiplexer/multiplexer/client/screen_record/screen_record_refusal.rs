use super::*;

pub fn refusal_text(record: &Value) -> Option<String> {
    let what = record.get("what").and_then(|value| value.as_str())?;
    if what != "the client and the holder do not agree on the contract" {
        return None;
    }
    let inputs = record.get("inputs").cloned().unwrap_or(Value::Null);
    let outputs = record.get("outputs").cloned().unwrap_or(Value::Null);
    let said = |value: &Value, key: &str| {
        value
            .get(key)
            .and_then(|one| one.as_str())
            .unwrap_or("")
            .to_string()
    };
    let safe = record
        .get("result")
        .and_then(|result| result.get("safe-path"))
        .and_then(|one| one.as_str())
        .unwrap_or("finish the session and restart the holder");
    Some(format!(
        "the contracts differ — this client is {} and {}, the holder is {} and {}; {}",
        said(&inputs, "client-holder-contract"),
        said(&inputs, "client-event-contract"),
        said(&outputs, "holder-holder-contract"),
        said(&outputs, "holder-event-contract"),
        safe
    ))
}

pub(crate) fn take_record(screen: &mut Screen, line: &str) -> Option<String> {
    let record: Value = match serde_json::from_str(line) {
        Ok(found) => found,
        Err(_) => return None,
    };
    if let Some(why) = refusal_text(&record) {
        return Some(why);
    }
    let kind = record.get("kind").and_then(|value| value.as_str()).unwrap_or("");
    let who = record.get("who").and_then(|value| value.as_str()).unwrap_or("");
    let what = record.get("what").and_then(|value| value.as_str()).unwrap_or("");
    let why = record.get("why").and_then(|value| value.as_str()).unwrap_or("");
    let seq = record.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
    screen
        .events
        .push(format!("#{} {} {}: {} — {}", seq, kind, who, what, why));
    if screen.events.len() > 50 {
        let extra = screen.events.len() - 50;
        screen.events.drain(0..extra);
    }
    if kind == "progress" {
        let text = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
            .unwrap_or("");
        screen.push_text(who, text);
        return None;
    }
    if what == "the workspace was read" {
        if screen.workspace_quiet {
            screen.workspace_quiet = false;
            screen.take_workspace_quiet(&record);
        } else {
            screen.take_workspace(&record);
        }
    }
    if what == "the git state was read" {
        screen.take_git(&record);
        return None;
    }
    if what == "the sessions were listed" {
        screen.take_sessions(&record);
        return None;
    }
    if what == "the pane was read back" {
        screen.take_rewind(&record);
        return None;
    }
    if what == "the editor was asked" {
        screen.take_editor(&record);
        return None;
    }
    if who == "holder" {
        screen.take_state(&record);
    }
    None
}

