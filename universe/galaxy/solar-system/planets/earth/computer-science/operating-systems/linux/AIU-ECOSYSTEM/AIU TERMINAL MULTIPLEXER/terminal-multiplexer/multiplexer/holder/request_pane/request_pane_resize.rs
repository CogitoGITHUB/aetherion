use crate::*;

pub(crate) fn request_pane_resize(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let cols = request
        .get("cols")
        .and_then(|value| value.as_u64())
        .unwrap_or(0) as u16;
    let rows = request
        .get("rows")
        .and_then(|value| value.as_u64())
        .unwrap_or(0) as u16;
    if cols == 0 || rows == 0 {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the window did not change",
            why: "the size asked for is not a size",
            how: "the columns and the rows were read and refused",
            inputs: json!({ "cols": cols, "rows": rows }),
            outputs: json!({}),
            result: json!({ "why": "a window needs columns and rows".to_string() }),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(false);
    }
    let area = request
        .get("area-rows")
        .and_then(|value| value.as_u64())
        .unwrap_or(rows as u64) as u16;
    session.cols = cols;
    session.rows = rows;
    session.area_rows = area;
    let told = session.tell_sizes();
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the window changed",
        why: "the client told the session the size of the terminal",
        how: "every pane's terminal was resized to its own place and every program was told to redraw",
        inputs: json!({ "cols": cols, "rows": rows, "area-rows": area, "client": client_name(&request) }),
        outputs: json!({ "panes": Value::Array(
            told.iter().map(|name| Value::from(name.clone())).collect::<Vec<Value>>()
        ) }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}
