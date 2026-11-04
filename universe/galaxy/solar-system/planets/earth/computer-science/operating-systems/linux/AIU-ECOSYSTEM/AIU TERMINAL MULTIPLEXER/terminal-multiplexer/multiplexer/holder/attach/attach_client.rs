use crate::*;

pub(crate) fn attach(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let client_event = request
        .get("event-contract")
        .and_then(|value| value.as_str())
        .unwrap_or("");
    let client_holder = request
        .get("holder-contract")
        .and_then(|value| value.as_str())
        .unwrap_or("");

    if client_event != EVENT_CONTRACT || client_holder != HOLDER_CONTRACT {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the client and the holder do not agree on the contract",
            why: "the versions exchanged at attach differ",
            how: "the two versions were compared and the attach was refused by name",
            inputs: json!({
                "client-event-contract": client_event,
                "client-holder-contract": client_holder
            }),
            outputs: json!({
                "holder-event-contract": EVENT_CONTRACT,
                "holder-holder-contract": HOLDER_CONTRACT
            }),
            result: json!({
                "safe-path": "finish the session and restart the holder, or run the old client"
            }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(false);
    }

    session.clients[at].attached = true;
    let role = request
        .get("role")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    session.clients[at].role = role;
    let record = session.state("the client attached and the contracts agree");
    session.write(&record);
    answer_client_more(session, at, &record);
    Ok(true)
}

pub(crate) fn client_name(request: &Value) -> String {
    request
        .get("client")
        .and_then(|value| value.as_str())
        .unwrap_or("a client")
        .to_string()
}

