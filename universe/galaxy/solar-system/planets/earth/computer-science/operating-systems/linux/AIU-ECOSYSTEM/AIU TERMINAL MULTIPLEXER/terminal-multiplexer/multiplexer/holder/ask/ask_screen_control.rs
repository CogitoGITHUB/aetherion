use crate::*;

pub(crate) fn ask_screen(
    session: &mut Session,
    at: usize,
    id: &str,
    words: &[String],
    kind: &str,
) -> Result<bool, String> {
    let screen = match session.screen_client() {
        Some(fd) => fd,
        None => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the agent's request was refused",
                why: "no screen is attached to this session, so there is nothing to drive",
                how: "the clients of the session were looked at, and none of them is a screen",
                inputs: json!({ "id": id, "words": words }),
                outputs: json!({}),
                result: json!({
                    "rule": "the agent drives the owner's own screen; without one there is nothing to drive"
                }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(true);
        }
    };
    let requester_fd = session.clients[at].fd;
    session.pending.push(Pending {
        id: id.to_string(),
        requester_fd,
    });
    let asked = json!({
        "kind": kind,
        "who": "agent",
        "inputs": { "id": id, "words": words },
        "outputs": {},
        "result": {}
    });
    let mut line = asked.to_string();
    line.push('\n');
    if let Err(why) = write_to(screen, line.as_bytes()) {
        session.pending.pop();
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the agent's request was refused",
            why: "the screen did not take the request",
            how: "the request was written to the screen's wire, and the write failed",
            inputs: json!({ "id": id, "words": words }),
            outputs: json!({}),
            result: json!({ "why": why }),
        });
        session.write(&record);
        answer_client(session, at, &record);
    }
    Ok(true)
}

pub(crate) fn control_result(session: &mut Session, _at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let data = request.get("data").cloned().unwrap_or(json!({}));
    let found = match session.pending.iter().position(|pending| pending.id == id) {
        Some(at) => at,
        None => return Ok(true),
    };
    let pending = session.pending.remove(found);
    let requester = match session
        .clients
        .iter()
        .position(|client| client.fd == pending.requester_fd)
    {
        Some(at) => at,
        None => return Ok(true),
    };
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the agent's request was answered",
        why: "the screen ran the words the agent sent",
        how: "the words ran on the owner's own screen, and the screen's answer came back",
        inputs: json!({ "id": id }),
        outputs: json!({ "data": data }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, requester, &record);
    Ok(true)
}

