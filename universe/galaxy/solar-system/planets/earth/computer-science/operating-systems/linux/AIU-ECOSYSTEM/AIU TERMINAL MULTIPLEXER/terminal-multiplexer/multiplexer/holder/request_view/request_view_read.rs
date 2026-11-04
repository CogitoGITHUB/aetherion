use crate::*;

pub(crate) fn request_view_read(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let since = request.get("since").and_then(|value| value.as_u64()).unwrap_or(0);
    let held = log::Log::records(&session.log_path)?;
    let mut sent = 0u64;
    for record in &held {
        let seq = record.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
        if seq <= since {
            continue;
        }
        let mut line = record.to_string();
        line.push('\n');
        if write_to(session.clients[at].fd, line.as_bytes()).is_err() {
            break;
        }
        sent += 1;
    }
    let done = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the records were read from the log",
        why: "the client asked for the records",
        how: "the log file was read back and the records after since were sent",
        inputs: json!({ "since": since }),
        outputs: json!({ "sent": sent }),
        result: json!({}),
    });
    session.write(&done);
    answer_client(session, at, &done);
    Ok(true)
}
