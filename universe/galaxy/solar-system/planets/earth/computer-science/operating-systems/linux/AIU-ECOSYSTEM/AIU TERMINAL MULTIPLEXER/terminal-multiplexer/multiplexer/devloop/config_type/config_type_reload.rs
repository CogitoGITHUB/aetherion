use super::*;

/// Reload answers what one look at the config file found.
pub enum Reload {
    /// Unchanged is the file as it was: nothing to do.
    Unchanged,
    /// Changed carries the config the file now holds: the caller applies it.
    Changed(Config),
    /// Broken carries the reason the file could not be used. The config in
    /// force stays in force.
    Broken(String),
}

/// Stamp is what tells one reading of a file from the next: when it was last
/// written and how long it is. No clock is read here.
#[derive(Clone, Copy, PartialEq)]
pub(crate) struct Stamp {
    pub(crate) mtime: SystemTime,
    pub(crate) len: u64,
}

/// stamp_of answers the stamp of one file, or None when it is not there.
pub(crate) fn stamp_of(path: &Path) -> Option<Stamp> {
    let meta = std::fs::metadata(path).ok()?;
    Some(Stamp {
        mtime: meta.modified().ok()?,
        len: meta.len(),
    })
}

