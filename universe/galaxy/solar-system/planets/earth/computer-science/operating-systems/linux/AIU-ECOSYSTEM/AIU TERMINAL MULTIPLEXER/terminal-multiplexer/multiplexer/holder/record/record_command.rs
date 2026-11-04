use crate::*;

/// command_record answers the command one pane was given and what that pane
/// printed after it: the two parts of one record, read from the log. A pane
/// with no command yet answers nothing, and the bundle carries neither part.
pub(crate) fn command_record(session: &Session, pane: &str) -> (String, String) {
    if pane.is_empty() {
        return (String::new(), String::new());
    }
    let held = match log::Log::records(&session.log_path) {
        Ok(held) => held,
        Err(_) => return (String::new(), String::new()),
    };
    let mut command = String::new();
    let mut at = 0;
    for (number, record) in held.iter().enumerate() {
        let of_pane = record
            .get("inputs")
            .and_then(|inputs| inputs.get("pane"))
            .and_then(|value| value.as_str());
        let is_command = record.get("kind").and_then(|value| value.as_str()) == Some("command");
        if is_command && of_pane == Some(pane) {
            command = record
                .get("inputs")
                .and_then(|inputs| inputs.get("command"))
                .and_then(|value| value.as_str())
                .unwrap_or("")
                .to_string();
            at = number + 1;
        }
    }
    if command.is_empty() {
        return (String::new(), String::new());
    }
    let mut said: Vec<String> = Vec::new();
    for record in held.iter().skip(at) {
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            said.push(text.to_string());
        }
    }
    (command, said.join("\n"))
}

