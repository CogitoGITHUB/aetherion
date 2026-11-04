use crate::*;

/// kill_pane ends a shell for good: the pane is removed and its terminal is
/// closed. This is the separate word from close/hide (TODO item 45), and
/// nothing uses it by accident.
pub(crate) fn kill_pane(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let name = request
        .get("name")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let at_pane = match session.panes.iter().position(|pane| pane.name == name) {
        Some(found) => found,
        None => {
            a_fail(session, at, "the pane was not killed",
                format!("there is no pane named {}", name),
                json!({ "name": name }));
            return Ok(true);
        }
    };
    let pane = session.panes.remove(at_pane);
    close(pane.shell.master);
    let record = session.record(Fields {
        kind: "info",
        who: &pane.name,
        what: "the pane was killed",
        why: "the owner asked to kill it for good",
        how: "the terminal was closed and the shell is ended; it will not come back",
        inputs: json!({ "name": pane.name.clone() }),
        outputs: json!({ "panes": session.panes.len() }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

/// show_pane brings a hidden pane back: its shell keeps running, and it
/// becomes drawn again.
pub(crate) fn show_pane(session: &mut Session, at: usize, name: &str) -> Result<bool, String> {
    let mut shown = false;
    for pane in session.panes.iter_mut() {
        if pane.name == name && pane.hidden {
            pane.hidden = false;
            shown = true;
            break;
        }
    }
    if !shown {
        a_fail(session, at, "the pane was not shown back",
            format!("there is no hidden pane named {}", name),
            json!({ "name": name }));
        return Ok(true);
    }
    if !session.tabs.contains(&session.panes.iter().find(|pane| pane.name == name).unwrap().tab) {
        let tab = session.panes.iter().find(|pane| pane.name == name).unwrap().tab.clone();
        session.tabs.push(tab);
    }
    let record = session.record(Fields {
        kind: "info",
        who: name,
        what: "the pane was shown again",
        why: "the owner asked to bring it back",
        how: "the hidden pane is drawn again and its shell was never ended",
        inputs: json!({ "name": name }),
        outputs: json!({}),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

/// rewind answers how one pane looked at one record: the lines that pane had
/// said by then, read from the journal. The answer is a record like every
/// other op's answer, and it touches no pane: a look back cannot change what
/// the session is doing.
pub(crate) fn rewind(session: &mut Session, at: usize, request: &Value) -> Result<bool, String> {
    let pane = request
        .get("pane")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    let until = request.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
    if pane.is_empty() {
        let record = session.record(Fields {
            kind: "fail",
            who: "holder",
            what: "the pane was not read back",
            why: "a rewind needs the name of the pane",
            how: "the request was read and the pane's name was empty",
            inputs: json!({ "seq": until }),
            outputs: json!({}),
            result: json!({}),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let held = log::Log::records(&session.log_path)?;
    let lines = pane_text_at(&held, &pane, until, REWIND_LINES);
    let count = lines.len();
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the pane was read back",
        why: "the owner chose a record and asked how the pane stood at it",
        how: "the journal was read up to that seq, and the pane's own lines were \
              taken from it; no pane was touched and no record was written for it",
        inputs: json!({ "pane": pane, "seq": until }),
        outputs: json!({ "pane": pane, "seq": until, "count": count, "lines": lines }),
        result: json!({ "says": "a look back changes nothing" }),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

