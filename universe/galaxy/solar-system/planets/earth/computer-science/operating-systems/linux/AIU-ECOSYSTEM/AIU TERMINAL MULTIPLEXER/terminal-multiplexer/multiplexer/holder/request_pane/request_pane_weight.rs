use crate::*;

pub(crate) fn request_pane_weight(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    // A pane wants more of the space, or less of it: the weight is
    // the pane's share, and the layout file keeps it.
    let name = request
        .get("pane")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let weight = request
        .get("weight")
        .and_then(|value| value.as_u64())
        .unwrap_or(0) as u16;
    let found = session.panes.iter().position(|pane| pane.name == name);
    let at = match found {
        Some(at) => at,
        None => {
            let record = session.record(Fields {
                kind: "fail",
                who: "holder",
                what: "the pane did not grow",
                why: "there is no pane of that name",
                how: "the name was looked for among the open panes and refused",
                inputs: json!({ "pane": name }),
                outputs: json!({}),
                result: json!({ "why": format!("there is no pane named {}", name) }),
            });
            session.write(&record);
            answer_client(session, at, &record);
            return Ok(true);
        }
    };
    if weight == 0 {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the pane did not grow",
            why: "a pane wants at least one part of the space",
            how: "the weight was read and refused",
            inputs: json!({ "pane": name, "weight": weight }),
            outputs: json!({}),
            result: json!({ "why": "a pane wants at least one part of the space" }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let before = session.panes[at].weight;
    session.panes[at].weight = weight;
    let told = session.tell_sizes();
    // The shape is written back where it was read: the layout file
    // IS the session's shape.
    let written = match session.layout_path.clone() {
        Some(path) => layout::write(&path, &session.direction, &session.shape()),
        None => Ok(()),
    };
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the pane changed its size",
        why: "the client asked for a different share of the space",
        how: "the weight was kept, every pane was given the size of its own place, and the layout file was written back",
        inputs: json!({ "pane": name, "weight": weight, "before": before }),
        outputs: json!({ "panes": Value::Array(
            told.iter().map(|one| Value::from(one.clone())).collect::<Vec<Value>>()
        ) }),
        result: json!({ "written": written.is_ok() }),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
