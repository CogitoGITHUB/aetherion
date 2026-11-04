
use serde_json::{json, Value};
use std::path::{Path, PathBuf};

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

pub fn dir_of(state_dir: &Path) -> PathBuf {
    state_dir
        .parent()
        .map(|found| found.to_path_buf())
        .unwrap_or_else(|| state_dir.to_path_buf())
}

pub fn name_of(state_dir: &Path) -> String {
    state_dir
        .file_name()
        .map(|found| found.to_string_lossy().to_string())
        .unwrap_or_default()
}

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
