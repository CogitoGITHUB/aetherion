use crate::*;

pub(crate) fn request_pane_rename(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let kind = request
        .get("kind")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let to = request
        .get("to")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if name.is_empty() || to.is_empty() {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the name did not change",
            why: "a rename needs the old name and the new one",
            how: "the names were read and refused",
            inputs: json!({ "kind": kind, "name": name, "to": to }),
            outputs: json!({}),
            result: json!({ "why": "a rename needs the old name and the new one".to_string() }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let mut changed: Vec<String> = Vec::new();
    if kind == "tab" {
        for tab in session.tabs.iter_mut() {
            if *tab == name {
                *tab = to.clone();
                changed.push(name.clone());
            }
        }
        for pane in session.panes.iter_mut() {
            if pane.tab == name {
                pane.tab = to.clone();
            }
        }
    } else {
        for pane in session.panes.iter_mut() {
            if pane.name == name {
                pane.name = to.clone();
                changed.push(name.clone());
            }
        }
    }
    if changed.is_empty() {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the name did not change",
            why: "there is nothing of that name to rename",
            how: "the name was looked for and refused by name",
            inputs: json!({ "kind": kind, "name": name, "to": to }),
            outputs: json!({}),
            result: json!({ "why": format!("there is no {} named {}", kind, name) }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the name changed",
        why: "the client asked for another name",
        how: "the name was looked for and replaced",
        inputs: json!({ "kind": kind, "name": name, "to": to, "client": client_name(&request) }),
        outputs: json!({ "renamed": Value::Array(
            changed.iter().map(|n| Value::from(n.clone())).collect::<Vec<Value>>()
        ) }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
