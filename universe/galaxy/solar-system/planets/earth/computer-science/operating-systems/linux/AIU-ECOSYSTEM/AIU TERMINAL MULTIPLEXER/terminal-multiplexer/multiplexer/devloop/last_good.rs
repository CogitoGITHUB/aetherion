// One job: the last good bake — the path of the last baked config that passed
// its check, the way to record a new one, and the way to read one back.
//
// A bake that goes wrong must never ship: the last good stays the last good,
// and the bad one is kept beside it so the owner can look at it. The rule is
// one line: the last good bake is kept.
//
// This file does not decide what good is. The bake asks that question — it
// reads its own file back — and calls keep_last_good only when the answer is
// yes, exactly as the editor's last-good area leaves the check to its caller.

use std::path::{Path, PathBuf};

/// RECORD is the file in the state directory that holds the path of the last
/// good bake: one line, the path.
pub const RECORD: &str = "last-good";

/// last_good answers the path of the last good bake, or None when there has
/// never been one.
pub fn last_good(state_dir: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(state_dir.join(RECORD)).ok()?;
    let path = text.trim();
    if path.is_empty() {
        None
    } else {
        Some(PathBuf::from(path))
    }
}

/// keep_last_good records a path as the last good bake. Called only when the
/// bake has already been found good.
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

/// read_text reads a recorded path's file back, so a caller holds the text of
/// the bake it has just recorded, or of the last good one.
pub fn read_text(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path)
        .map_err(|why| format!("{} cannot be read: {}", path.display(), why))
}

#[cfg(test)]
#[path = "last_good_test/last_good_test_behavior.rs"]
mod tests;
