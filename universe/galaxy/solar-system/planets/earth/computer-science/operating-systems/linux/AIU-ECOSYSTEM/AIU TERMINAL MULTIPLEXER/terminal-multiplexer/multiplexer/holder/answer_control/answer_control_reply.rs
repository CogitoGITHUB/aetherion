use crate::*;

/// control is the agent's door into the screen: the words the agent sent,
/// and the screen's answer. A change needs the human's token, and the holder
/// checks it itself (rule 07): the caller's word is not taken for what it
/// does.
///
/// The holder holds no screen of its own. The words run on the owner's own
/// screen, so the agent and the owner drive the same code.
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

/// view is the agent's read of the screen: what the owner sees. A read is
/// free, so it needs no token.
pub(crate) fn view(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let id = request
        .get("id")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    ask_screen(session, at, &id, &[], "view")
}

/// list_sessions answers what stands in the sessions directory: every session,
/// and whether a holder holds it. It is a read: nothing is made or ended.
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

/// a_fail answers one refusal to the client that asked, and says the rule that
/// refused: every one of the four session commands answers by name.
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

/// session_command runs one of the owner's four session commands: create,
/// rename, kill. The fourth, the listing, is list_sessions above.
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

