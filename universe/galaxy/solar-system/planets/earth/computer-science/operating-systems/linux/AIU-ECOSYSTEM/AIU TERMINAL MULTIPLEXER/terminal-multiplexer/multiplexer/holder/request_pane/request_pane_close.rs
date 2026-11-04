use crate::*;

pub(crate) fn request_pane_close(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let kind = request
        .get("kind")
        .and_then(|value| value.as_str())
        .unwrap_or("pane")
        .to_string();
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let mut hidden: Vec<String> = Vec::new();
    for pane in session.panes.iter_mut() {
        let chosen = if kind == "tab" {
            pane.tab == name
        } else {
            pane.name == name
        };
        if chosen && !pane.hidden {
            pane.hidden = true;
            hidden.push(pane.name.clone());
        }
    }
    if kind == "tab" {
        session.tabs.retain(|tab| *tab != name);
    }
    if hidden.is_empty() {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "nothing was hidden",
            why: "there is no drawn pane of that name, or it is already hidden",
            how: "the panes were looked at and none of them is the one named",
            inputs: json!({ "kind": kind, "name": name }),
            outputs: json!({}),
            result: json!({ "comes-back": "pane show NAME brings a hidden pane back" }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the pane was hidden",
        why: "the owner closed it",
        how: "it stops being drawn and its shell keeps running; a kill is \
              the separate word",
        inputs: json!({ "kind": kind, "name": name,
                        "client": client_name(&request) }),
        outputs: json!({ "hidden": Value::Array(
            hidden.iter().map(|one| Value::from(one.clone())).collect::<Vec<Value>>()
        ) }),
        result: json!({ "comes-back": "pane show NAME" }),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
