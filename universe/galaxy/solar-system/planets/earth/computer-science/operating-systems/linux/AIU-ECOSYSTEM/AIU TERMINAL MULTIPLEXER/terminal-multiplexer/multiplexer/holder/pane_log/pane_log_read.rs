use crate::*;

/// pane_log_tail answers the last words one pane's program said, as the
/// session's log holds them. It reads the log and never the drawing.
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

/// REWIND_LINES is how many of a pane's lines a rewind shows: the newest ones
/// up to the record the owner chose, so the view is a page and not a flood.
pub(crate) const REWIND_LINES: usize = 200;

/// pane_text_at answers the lines one pane had said by one record, read from
/// the log: every record of that pane up to and including the seq, and never
/// one after it. The newest REWIND_LINES of them are the answer, so a long
/// session still reads as a page.
///
/// This is a read of the journal and nothing else: it changes no pane and
/// writes no record, so looking back cannot change what the pane is doing.
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

