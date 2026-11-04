use crate::*;

pub(crate) fn request_client_detach(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    session.clients[at].attached = false;
    let record = session.record(Fields {
        kind: "info",
        who: "client",
        what: "the client detached",
        why: "the client asked to detach",
        how: "the client was answered and the connection was closed",
        inputs: json!({ "client": client_name(&request) }),
        outputs: json!({}),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(false)
}
