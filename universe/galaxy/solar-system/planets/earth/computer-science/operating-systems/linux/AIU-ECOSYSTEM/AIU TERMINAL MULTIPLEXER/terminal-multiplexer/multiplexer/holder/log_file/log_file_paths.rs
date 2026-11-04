use super::*;

/// seq_of answers the seq a record line carries, and 0 when it carries none:
/// the trim needs the numbers only to say what it let go.
pub(crate) fn seq_of(line: &str) -> u64 {
    match serde_json::from_str::<serde_json::Value>(line) {
        Ok(value) => value.get("seq").and_then(|one| one.as_u64()).unwrap_or(0),
        Err(_) => 0,
    }
}

/// private_dir makes a directory and keeps it the owner's alone: 0700. It is
/// called on the state directory at every start, so a directory made before
/// the rule was written is made private too.
pub fn private_dir(path: &Path) -> Result<(), String> {
    std::fs::create_dir_all(path)
        .map_err(|why| format!("the directory {} cannot be made: {}", path.display(), why))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
        .map_err(|why| format!("the directory {} cannot be made private: {}", path.display(), why))
}

/// private_file keeps one file the owner's alone: 0600.
pub fn private_file(path: &Path) -> Result<(), String> {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(|why| format!("the file {} cannot be made private: {}", path.display(), why))
}

