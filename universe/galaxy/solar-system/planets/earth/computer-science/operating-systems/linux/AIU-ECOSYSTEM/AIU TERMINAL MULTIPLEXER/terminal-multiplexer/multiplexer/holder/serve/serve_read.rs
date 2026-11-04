use crate::*;

pub(crate) fn read_shell(session: &mut Session, pane_at: usize) -> Result<bool, String> {
    let mut buffer = [0u8; 4096];
    let got = match session.panes[pane_at].shell.read(&mut buffer) {
        Ok(got) => got,
        Err(why) => {
            let pane_name = session.panes[pane_at].name.clone();
            let record = session.record(Fields {
                kind: "info",
                who: &pane_name,
                what: "the pane ended",
                why: "its program is gone and its terminal is closed",
                how: "the read of the terminal failed and the pane was let go",
                inputs: json!({ "pane": pane_name }),
                outputs: json!({}),
                result: json!({ "why": why }),
            });
            session.write(&record);
            return Ok(false);
        }
    };
    if got == 0 {
        return Ok(false);
    }
    let text = tty::plain(&buffer[..got]);
    let pane_name = session.panes[pane_at].name.clone();
    let record = session.record(Fields {
        kind: "progress",
        who: &pane_name,
        what: "the shell wrote",
        why: "the shell had something to say",
        how: "the master read the bytes and the escapes were left out",
        inputs: json!({ "bytes": got, "pane": pane_name }),
        outputs: json!({ "text": text, "raw": String::from_utf8_lossy(&buffer[..got]).to_string() }),
        result: json!({}),
    });
    session.write(&record);
    Ok(true)
}

pub(crate) fn close_pane(session: &mut Session, pane_at: usize) {
    let pane = session.panes.remove(pane_at);
    close(pane.shell.master);
    let record = session.record(Fields {
        kind: "info",
        who: &pane.name,
        what: "the pane ended",
        why: "its program is gone",
        how: "the terminal was closed and the pane was let go",
        inputs: json!({ "pane": pane.name.clone() }),
        outputs: json!({ "panes": session.panes.len() }),
        result: json!({}),
    });
    session.write(&record);
}

pub(crate) fn read_client(session: &mut Session, at: usize) -> Result<bool, String> {
    let mut buffer = [0u8; 4096];
    let got = match read_from(session.clients[at].fd, &mut buffer) {
        Ok(got) => got,
        Err(why) => {
            let record = session.record(Fields {
                kind: "info",
                who: "holder",
                what: "the client is gone",
                why: "its socket broke while the holder was reading it",
                how: "the read failed and the client was let go",
                inputs: json!({ "fd": session.clients[at].fd }),
                outputs: json!({}),
                result: json!({ "why": why }),
            });
            session.write(&record);
            return Ok(false);
        }
    };
    if got == 0 {
        return Ok(false);
    }
    let text = String::from_utf8_lossy(&buffer[..got]).to_string();
    session.clients[at].pending.push_str(&text);

    let mut keep = true;
    while let Some(at_newline) = session.clients[at].pending.find('\n') {
        let line: String = session.clients[at].pending[..at_newline].to_string();
        session.clients[at].pending = session.clients[at].pending[at_newline + 1..].to_string();
        if !answer(session, at, line.trim())? {
            keep = false;
        }
    }
    Ok(keep)
}

