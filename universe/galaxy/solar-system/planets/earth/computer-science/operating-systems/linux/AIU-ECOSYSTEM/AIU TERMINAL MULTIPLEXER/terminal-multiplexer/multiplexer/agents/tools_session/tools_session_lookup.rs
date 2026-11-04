use super::*;

pub(crate) fn sessions(sessions_dir: &Path) -> Result<Value, String> {
    let entries = std::fs::read_dir(sessions_dir)
        .map_err(|why| format!("the sessions directory {} cannot be read: {}", sessions_dir.display(), why))?;
    let mut held: Vec<Value> = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let name = match path.file_name() {
            Some(found) => found.to_string_lossy().to_string(),
            None => continue,
        };
        let socket = path.join("holder.sock");
        if !socket.exists() {
            held.push(json!({
                "session": name,
                "held": false,
                "why": "no holder holds this session"
            }));
            continue;
        }
        let request = json!({ "op": "state", "client": "mux-mcp/1" });
        match ask_holder(&path, request) {
            Ok(records) => {
                let state = records
                    .last()
                    .cloned()
                    .unwrap_or(Value::Object(serde_json::Map::new()));
                let mut said = json!({ "session": name, "held": true });
                if let Some(outputs) = state.get("outputs") {
                    said["state"] = outputs.clone();
                }
                held.push(said);
            }
            Err(why) => held.push(json!({
                "session": name,
                "held": false,
                "why": why
            })),
        }
    }
    Ok(json!({ "sessions": held }))
}

pub(crate) fn named_session(arguments: &Value, sessions_dir: &Path) -> Result<PathBuf, String> {
    let name = arguments
        .get("session")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string();
    if name.is_empty() {
        return Err("this tool needs the name of a session".to_string());
    }
    if name.contains('/') || name.contains("..") {
        return Err(format!("{} is not a session name", name));
    }
    Ok(sessions_dir.join(&name))
}

pub(crate) fn session_name(arguments: &Value) -> String {
    arguments
        .get("session")
        .and_then(|value| value.as_str())
        .unwrap_or("")
        .to_string()
}

pub(crate) fn ask_holder(session_dir: &Path, request: Value) -> Result<Vec<Value>, String> {
    let socket = session_dir.join("holder.sock");
    wire::wait_for_socket(&socket)?;
    let fd = wire::connect(&socket)?;
    let asked = wire::ask(fd, &request);
    if let Err(why) = asked {
        wire::close(fd);
        return Err(why);
    }
    let mut held: Vec<Value> = Vec::new();
    let mut pending = String::new();
    let mut buffer = [0u8; 8192];
    loop {
        let got = match wire::read(fd, &mut buffer) {
            Ok(count) => count,
            Err(why) => {
                wire::close(fd);
                return Err(why);
            }
        };
        if got == 0 {
            break;
        }
        pending.push_str(&String::from_utf8_lossy(&buffer[..got]));
        let mut last = false;
        while let Some(at) = pending.find('\n') {
            let line = pending[..at].trim().to_string();
            pending = pending[at + 1..].to_string();
            if line.is_empty() {
                continue;
            }
            match serde_json::from_str::<Value>(&line) {
                Ok(value) => {
                    if value
                        .get("result")
                        .and_then(|result| result.get("final"))
                        .and_then(|flag| flag.as_bool())
                        .unwrap_or(false)
                    {
                        last = true;
                    }
                    held.push(value);
                }
                Err(why) => {
                    wire::close(fd);
                    return Err(format!("the holder sent a line that is not a record: {}", why));
                }
            }
        }
        if last {
            break;
        }
    }
    wire::close(fd);
    Ok(held)
}
