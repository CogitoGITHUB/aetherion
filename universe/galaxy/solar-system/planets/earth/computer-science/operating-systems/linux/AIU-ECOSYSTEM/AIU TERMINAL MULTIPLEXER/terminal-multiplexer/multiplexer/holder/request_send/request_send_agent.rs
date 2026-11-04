use crate::*;

pub(crate) fn request_send_agent(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    // The picked text goes to the agent that is open, in the
    // bundle: the same shape every program sends. The bundle is
    // built here, where the redaction seam is, and the text
    // leaves the multiplexer through the agent's own terminal.
    let selection = request
        .get("selection")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let target = request
        .get("target")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let why = request
        .get("why")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let from = request
        .get("from")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    // The command record: the command the pane was given and what
    // that pane printed after it, read from the log — the truth, and
    // never a copy the screen made by hand.
    let (command, output) = command_record(session, &from);
    let made = bundle::Bundle::make(
        "aiu-multiplexer",
        "aiu-ecosystem",
        &target,
        &selection,
        "",
        "",
        "",
        &why,
    );
    let text = match made {
        Some(bundle) => {
            let bundle = bundle.carrying(&command, &output);
            let text = format!("{}\n", bundle.text());
            // The seam has already been through the bundle; this
            // asks the seam again, and a text that would still
            // change is refused by name instead of written to an
            // agent's terminal.
            if !bundle::carries_no_secret(&text) {
                let record = session.record(Fields {
                    kind: "fail",
                    who: "holder",
                    what: "the picked text was not sent",
                    why: "the bundle would carry a secret",
                    how: "the redaction seam was asked again and the text would change",
                    inputs: json!({ "target": target, "from": from }),
                    outputs: json!({}),
                    result: json!({ "why": "the bundle would carry a secret" }),
                });
                session.write(&record);
                answer_client(session, at, &record);
                return Ok(false);
            }
            text
        }
        None => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the picked text was not sent",
                why: "the bundle could not be made",
                how: "the redaction seam refused the text",
                inputs: json!({ "target": target }),
                outputs: json!({}),
                result: json!({ "why": "the bundle could not be made" }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(false);
        }
    };
    // The destinations: the multiplexer's own agent and the editor's
    // agent. Both panes run the same agent program, so one bundle
    // serves both and neither is told which one it is.
    let destinations: Vec<usize> = AGENT_PANES
        .iter()
        .filter_map(|name| session.panes.iter().position(|pane| &pane.name == name))
        .collect();
    if destinations.is_empty() {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the picked text was not sent",
            why: "there is no agent pane open",
            how: "the panes were looked for and no agent was found",
            inputs: json!({ "target": target, "from": from }),
            outputs: json!({}),
            result: json!({ "why": "there is no agent pane open" }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(false);
    }
    let mut went: Vec<String> = Vec::new();
    for pane_index in destinations {
        let pane_name = session.panes[pane_index].name.clone();
        let sent = session.panes[pane_index].shell.send(text.as_bytes());
        let record = session.record(Fields {
            kind: if sent.is_ok() { "info" } else { "fail" },
            who: "holder",
            what: "the bundle went to the agent",
            why: "the owner sent the picked text",
            how: "the bundle was written to the agent's terminal",
            inputs: json!({ "bytes": text.len(), "pane": pane_name.clone(), "target": target }),
            outputs: json!({}),
            result: json!({}),
        });
        session.write(&record);
        if sent.is_ok() {
            went.push(pane_name);
        }
    }
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the bundle went to the agents",
        why: "the owner sent the picked text to the agents",
        how: "the same bundle was written to every agent pane that is open",
        inputs: json!({ "target": target, "from": from, "agents": went.len() }),
        outputs: json!({ "agents": went.join(",") }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
