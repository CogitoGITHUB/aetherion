use crate::*;

pub(crate) fn request_view_editor(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    // The client asks the editor what it owns: the editor's own
    // server is asked, over the editor's own wire, and the editor's
    // own words come back. The ask is read-only, and the editor's
    // own engine checks that before it runs anything.
    let command: Vec<String> = request
        .get("command")
        .and_then(|value| value.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|one| one.as_str().map(|text| text.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let capability = request
        .get("capability")
        .and_then(|value| value.as_str())
        .unwrap_or("dashboard")
        .to_string();
    let answer = editor::ask(&command, &capability);
    let record = session.record(Fields {
        kind: if answer.ok { "info" } else { "fail" },
        who: "holder",
        what: "the editor was asked",
        why: "the client asked what the editor owns",
        how: "the editor's own server was asked, over its own wire, and it only reads",
        inputs: json!({ "capability": capability, "command": command }),
        outputs: json!({ "editor": answer.data }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
