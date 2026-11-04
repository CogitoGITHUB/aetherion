
use std::path::{Path, PathBuf};

pub const RECORD: &str = "last-good";

pub fn last_good(state_dir: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(state_dir.join(RECORD)).ok()?;
    let path = text.trim();
    if path.is_empty() {
        None
    } else {
        Some(PathBuf::from(path))
    }
}

pub fn keep_last_good(state_dir: &Path, path: &Path) -> Result<(), String> {
    std::fs::create_dir_all(state_dir).map_err(|why| {
        format!(
            "the state directory {} cannot be made: {}",
            state_dir.display(),
            why
        )
    })?;
    let record = state_dir.join(RECORD);
    let text = format!("{}\n", path.display());
    std::fs::write(&record, text.as_bytes())
        .map_err(|why| format!("{} cannot be written: {}", record.display(), why))
}

pub fn read_text(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path)
        .map_err(|why| format!("{} cannot be read: {}", path.display(), why))
}

#[cfg(test)]
#[path = "last_good_test/last_good_test_behavior.rs"]
mod tests;
