use crate::*;

pub(crate) fn request_send_text(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let data = request.get("data").and_then(|value| value.as_str()).unwrap_or("");
    let wanted_pane = request
        .get("pane")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    let target = match pane_at(session, wanted_pane) {
        Ok(found) => found,
        Err(why) => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the pane took no bytes",
                why: "there is no pane of that name",
                how: "the pane was looked for and refused by name",
                inputs: json!({ "pane": wanted_pane }),
                outputs: json!({}),
                result: json!({ "why": why }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(false);
        }
    };
    let pane_name = session.panes[target].name.clone();
    let sent = match session.panes[target].shell.send(data.as_bytes()) {
        Ok(()) => true,
        Err(why) => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the shell took no bytes",
                why: "the terminal refused the data",
                how: "the bytes were written to the master",
                inputs: json!({ "bytes": data.len() }),
                outputs: json!({}),
                result: json!({ "why": why }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            false
        }
    };
    if sent {
        session.panes[target].typed.push_str(data);
        let typed = session.panes[target].typed.clone();
        let command = match typed.rfind('\n') {
            Some(at) => Some(typed[..at].to_string()),
            None => None,
        };
        if let Some(command) = command {
            let kept = typed.rsplit('\n').next().unwrap_or("").to_string();
            session.panes[target].typed = kept;
            let record = session.record(Fields {
                kind: "command",
                who: "holder",
                what: "the pane was given a command",
                why: "the owner typed it in that pane",
                how: "the typed text was read up to the newline that ended it",
                inputs: json!({ "pane": pane_name.clone(), "command": command }),
                outputs: json!({}),
                result: json!({}),
            });
            session.write(&record);
        }
        let record = session.record(Fields {
            kind: "info",
            who: "client",
            what: "the data went to the shell",
            why: "the client asked to send",
            how: "the bytes were written to the terminal",
            inputs: json!({ "bytes": data.len(), "client": client_name(&request), "pane": pane_name }),
            outputs: json!({}),
            result: json!({}),
        });
        session.write(&record);
        answer_client(session, at, &record);
    }
    Ok(true)
}
