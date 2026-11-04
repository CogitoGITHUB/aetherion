use crate::*;

pub(crate) fn control(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let words: Vec<String> = request
        .get("words")
        .and_then(|value| value.as_array())
        .map(|list| {
            list.iter()
                .filter_map(|one| one.as_str().map(|text| text.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let given = request
        .get("confirm")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if !session.token_matches(&given) {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the agent's change was refused",
            why: "a change needs the human's token, and it was refused",
            how: "the token was compared with the session's own token",
            inputs: json!({ "id": id, "words": words }),
            outputs: json!({}),
            result: json!({
                "rule": "rule 07: read is free, a change needs the human's token"
            }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    ask_screen(session, at, &id, &words, "control")
}

pub(crate) fn view(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    ask_screen(session, at, &id, &[], "view")
}

pub(crate) fn list_sessions(session: &mut Session, at: usize) -> Result<bool, String> {
    let list = sessions::listing(&session.sessions_dir);
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the sessions were listed",
        why: "the owner asked what stands",
        how: "the sessions directory was read and every session's socket was tried",
        inputs: json!({ "sessions-dir": session.sessions_dir.to_string_lossy() }),
        outputs: list,
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

pub(crate) fn a_fail(session: &mut Session, at: usize, what: &str, why: String, inputs: Value) {
    let record = session.record(Fields {
        kind: "fail",
        who: "holder",
        what: what,
        why: &why,
        how: "the word was read, checked, and refused by name",
        inputs,
        outputs: json!({}),
        result: json!({ "why": why }),
    });
    session.write(&record);
    answer_client(session, at, &record);
}

pub(crate) fn session_command(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let what = request
        .get("what")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if let Err(why) = sessions::check_name(&name) {
        a_fail(session, at, "the session command was refused", why,
            json!({ "what": what, "name": name }));
        return Ok(true);
    }
    match what.as_str() {
        "create" => create_session(session, at, &name),
        "rename" => rename_session(session, at, &name),
        "kill" => kill_session(session, at, &name),
        "show" => show_pane(session, at, &name),
        other => {
            a_fail(session, at, "the session command was refused",
                format!("{} is not one of create, rename, kill or show", other),
                json!({ "what": other, "name": name }));
            Ok(true)
        }
    }
}

