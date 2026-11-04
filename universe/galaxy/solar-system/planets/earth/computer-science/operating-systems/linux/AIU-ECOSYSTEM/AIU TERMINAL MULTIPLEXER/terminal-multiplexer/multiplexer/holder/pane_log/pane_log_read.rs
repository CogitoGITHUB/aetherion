use crate::*;

pub(crate) fn pane_log_tail(session: &Session, pane: &str, limit: usize) -> String {
    let held = match log::Log::records(&session.log_path) {
        Ok(held) => held,
        Err(_) => return String::new(),
    };
    let mut lines: Vec<String> = Vec::new();
    for record in held.iter().rev().take(limit).rev() {
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            lines.push(text.to_string());
        }
    }
    lines.join("\n")
}

pub(crate) const REWIND_LINES: usize = 200;

pub(crate) fn pane_text_at(held: &[Value], pane: &str, until: u64, limit: usize) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for record in held {
        let seq = record.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
        if seq > until {
            break;
        }
        if record.get("who").and_then(|value| value.as_str()) != Some(pane) {
            continue;
        }
        if let Some(text) = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
        {
            lines.push(text.to_string());
        }
    }
    let from = lines.len().saturating_sub(limit);
    lines.drain(0..from);
    lines
}

