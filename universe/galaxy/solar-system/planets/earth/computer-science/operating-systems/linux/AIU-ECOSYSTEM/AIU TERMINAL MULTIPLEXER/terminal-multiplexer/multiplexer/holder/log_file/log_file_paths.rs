use super::*;

pub(crate) fn seq_of(line: &str) -> u64 {
    match serde_json::from_str::<serde_json::Value>(line) {
        Ok(value) => value.get("seq").and_then(|one| one.as_u64()).unwrap_or(0),
        Err(_) => 0,
    }
}

pub fn private_dir(path: &Path) -> Result<(), String> {
    std::fs::create_dir_all(path)
        .map_err(|why| format!("the directory {} cannot be made: {}", path.display(), why))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
        .map_err(|why| format!("the directory {} cannot be made private: {}", path.display(), why))
}

pub fn private_file(path: &Path) -> Result<(), String> {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(|why| format!("the file {} cannot be made private: {}", path.display(), why))
}

