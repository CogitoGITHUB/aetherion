// One job: the sessions directory — the listing that says what stands, and the
// names a session may have (TODO item 49).
//
// A session IS a directory: the holder's state directory, with its log, its
// socket and its pid, under one sessions directory. The name of a session is
// the name of that directory, and nothing else names a session.
//
// This file only reads and names: the holder runs the four commands over it
// (create, rename, kill, list), and the file that holds the session's own
// objects stays where it is.

use serde_json::{json, Value};
use std::path::{Path, PathBuf};

/// check_name answers whether a name can be a session's, and the reason when it
/// cannot. A name is one path segment: no slash, no dot-dot, no leading dash,
/// and nothing that a shell would read as an option.
pub fn check_name(name: &str) -> Result<(), String> {
    if name.is_empty() {
        return Err("a session needs a name".to_string());
    }
    if name.contains('/') || name.contains("..") {
        return Err(format!("{} is not a session name: it holds a path", name));
    }
    if name.starts_with('-') || name.starts_with('.') {
        return Err(format!("{} is not a session name: it starts with {}",
            name, name.chars().next().unwrap_or('-')));
    }
    if name.contains(' ') || name.contains('\t') {
        return Err(format!("{} is not a session name: it holds a space", name));
    }
    Ok(())
}

/// dir_of answers the sessions directory a session stands in: the state
/// directory's own parent, unless the holder was given one.
pub fn dir_of(state_dir: &Path) -> PathBuf {
    state_dir
        .parent()
        .map(|found| found.to_path_buf())
        .unwrap_or_else(|| state_dir.to_path_buf())
}

/// name_of answers the name a session's directory gives it.
pub fn name_of(state_dir: &Path) -> String {
    state_dir
        .file_name()
        .map(|found| found.to_string_lossy().to_string())
        .unwrap_or_default()
}

/// stands answers the name of every session in the directory, sorted, and an
/// empty list when there is no directory yet: nothing has been made, which is
/// not an error.
pub fn stands(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if let Some(name) = path.file_name() {
                    names.push(name.to_string_lossy().to_string());
                }
            }
        }
    }
    names.sort();
    names
}

/// held answers whether a holder holds the session in this directory: the
/// socket is there and it answers a read. A socket left by a holder that was
/// killed is not a holder.
pub fn held(session: &Path) -> bool {
    let socket = session.join("holder.sock");
    if !socket.exists() {
        return false;
    }
    match super::connect(&socket) {
        Ok(fd) => {
            let answers = super::answers_holder(fd);
            super::close(fd);
            answers
        }
        Err(_) => false,
    }
}

/// listing answers what stands, one entry per session, in the shape the MCP
/// server's own list uses: the name, whether a holder holds it, and the reason
/// when none does.
pub fn listing(dir: &Path) -> Value {
    let mut entries: Vec<Value> = Vec::new();
    for name in stands(dir) {
        let session = dir.join(&name);
        if held(&session) {
            entries.push(json!({ "session": name, "held": true }));
        } else {
            entries.push(json!({
                "session": name,
                "held": false,
                "why": "no holder holds this session"
            }));
        }
    }
    json!({ "sessions": entries, "sessions-dir": dir.to_string_lossy() })
}

#[cfg(test)]
#[path = "sessions_test/sessions_test_behavior.rs"]
mod tests;
