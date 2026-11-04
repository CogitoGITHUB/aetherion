use crate::*;

/// create_session starts a holder for a new session: the same program, its own
/// state directory under the sessions directory, and its own socket. The new
/// holder lives on its own, so the session the owner is in does not carry it.
pub(crate) fn create_session(session: &mut Session, at: usize, name: &str) -> Result<bool, String> {
    let target = session.sessions_dir.join(name);
    if target.exists() {
        a_fail(session, at, "the session was not created",
            format!("a session named {} already stands", name),
            json!({ "name": name }));
        return Ok(true);
    }
    log::private_dir(&target)?;
    let program = std::env::current_exe()
        .map_err(|why| format!("this holder cannot say which program it is: {}", why))?;
    let child = std::process::Command::new(program)
        .arg("--state-dir").arg(&target)
        .arg("--sessions-dir").arg(&session.sessions_dir)
        .arg("--cols").arg(session.cols.to_string())
        .arg("--rows").arg(session.rows.to_string())
        .spawn();
    let pid = match child {
        Ok(found) => found.id(),
        Err(why) => {
            let _ = std::fs::remove_dir(&target);
            a_fail(session, at, "the session was not created",
                format!("a holder for {} could not be started: {}", name, why),
                json!({ "name": name }));
            return Ok(true);
        }
    };
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "a session was created",
        why: "the owner asked for a new session",
        how: "a holder was started for a new state directory under the sessions \
              directory, and it lives on its own",
        inputs: json!({ "name": name }),
        outputs: json!({ "session": name, "pid": pid,
                         "state-dir": target.to_string_lossy() }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

/// rename_session renames the session the owner is in: the state directory is
/// renamed, and the session's own paths follow it. The socket is already bound,
/// so the attached client keeps its connection through the rename.
///
/// Another session's name cannot be changed from here: its holder holds the
/// paths, and a rename under it would leave it writing to paths that are gone.
pub(crate) fn rename_session(session: &mut Session, at: usize, name: &str) -> Result<bool, String> {
    let from = session.state_dir.clone();
    let to = session.sessions_dir.join(name);
    let was = sessions::name_of(&from);
    if to.exists() {
        a_fail(session, at, "the session was not renamed",
            format!("a session named {} already stands", name),
            json!({ "name": name }));
        return Ok(true);
    }
    std::fs::rename(&from, &to).map_err(|why| {
        format!("the session {} cannot be renamed: {}", from.display(), why)
    })?;
    session.state_dir = to.clone();
    session.log_path = to.join("events.log");
    session.socket_path = to.join("holder.sock");
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the session was renamed",
        why: "the owner gave the session a new name",
        how: "the state directory was renamed and the session's own paths followed it",
        inputs: json!({ "from": was }),
        outputs: json!({ "session": name, "state-dir": to.to_string_lossy() }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    Ok(true)
}

/// kill_session ends another session for good: it asks that session's holder to
/// shut down, and that holder removes its own socket, pid and log as it leaves.
/// A session cannot kill itself: its directory cannot be removed under its own
/// feet, and saying so is better than removing half of it.
pub(crate) fn kill_session(session: &mut Session, at: usize, name: &str) -> Result<bool, String> {
    let own = sessions::name_of(&session.state_dir);
    if name == own {
        a_fail(
            session,
            at,
            "the session was not killed",
            format!(
                "{} is this session, and a session cannot remove the ground it stands on: \
                 leave it, close its last pane, or ask another session",
                name
            ),
            json!({ "name": name }),
        );
        return Ok(true);
    }
    let target = session.sessions_dir.join(name);
    if !target.exists() {
        a_fail(
            session,
            at,
            "the session was not killed",
            format!("there is no session named {}", name),
            json!({ "name": name }),
        );
        return Ok(true);
    }
    if !sessions::held(&target) {
        // No holder holds it: the directory is what is left of it, and a killed
        // session is gone for good.
        std::fs::remove_dir_all(&target).map_err(|why| {
            format!("the session {} cannot be removed: {}", target.display(), why)
        })?;
        let record = session.record(Fields {
            kind: "info",
            who: "holder",
            what: "a session was killed",
            why: "the owner asked for it and no holder held it",
            how: "the directory was removed; there was no holder to ask",
            inputs: json!({ "name": name }),
            outputs: json!({ "session": name, "held": false }),
            result: json!({}),
        });
        session.write(&record);
        answer_client(session, at, &record);
        return Ok(true);
    }
    let asked = ask_once(&target.join("holder.sock"),
        &json!({ "op": "shutdown", "client": "holder", "why": "the owner asked" }));
    match asked {
        Ok(answer) => {
            let record = session.record(Fields {
                kind: "info",
                who: "holder",
                what: "a session was killed",
                why: "the owner asked for it",
                how: "the other session's holder was asked to shut down, and it \
                      removes its own socket, pid and log as it leaves",
                inputs: json!({ "name": name }),
                outputs: json!({ "session": name, "answered": answer }),
                result: json!({}),
            });
            session.write(&record);
            answer_client(session, at, &record);
        }
        Err(why) => {
            a_fail(
                session,
                at,
                "the session was not killed",
                format!("the holder of {} did not answer, so nothing was removed: {}", name, why),
                json!({ "name": name }),
            );
        }
    }
    Ok(true)
}

/// shutdown ends the session: the record of it is answered first, then the
/// files the session owns are removed and the holder leaves. The workspace
/// directory is left alone: it is the shared engine's, not this session's.
pub(crate) fn shutdown(session: &mut Session, at: usize) -> Result<bool, String> {
    // What the session made is removed; what it did not make is named, never
    // deleted: the layout file may be the owner's own.
    let mut left: Vec<String> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&session.state_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name != "holder.sock" && name != "events.log" && name != "holder.pid" {
                left.push(name);
            }
        }
    }
    left.sort();
    let record = session.record(Fields {
        kind: "info",
        who: "holder",
        what: "the session is shutting down",
        why: "another session was asked to kill it",
        how: "the socket, the pid and the log are removed, what the session did \
              not make is named, and the holder leaves",
        inputs: json!({ "state-dir": session.state_dir.to_string_lossy() }),
        outputs: json!({ "socket": session.socket_path.to_string_lossy(),
                         "log": session.log_path.to_string_lossy(),
                         "left": left }),
        result: json!({}),
    });
    session.write(&record);
    answer_client(session, at, &record);
    for path in [&session.socket_path, &session.log_path] {
        let _ = std::fs::remove_file(path);
    }
    let _ = std::fs::remove_file(session.state_dir.join("holder.pid"));
    // The directory goes too when the session left nothing else in it.
    let _ = std::fs::remove_dir(&session.state_dir);
    std::process::exit(0);
}


