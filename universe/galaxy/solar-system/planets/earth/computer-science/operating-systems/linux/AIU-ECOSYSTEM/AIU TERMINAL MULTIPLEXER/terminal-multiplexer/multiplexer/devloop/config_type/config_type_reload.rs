use super::*;

pub enum Reload {
    Unchanged,
    Changed(Config),
    Broken(String),
}

#[derive(Clone, Copy, PartialEq)]
pub(crate) struct Stamp {
    pub(crate) mtime: SystemTime,
    pub(crate) len: u64,
}

pub(crate) fn stamp_of(path: &Path) -> Option<Stamp> {
    let meta = std::fs::metadata(path).ok()?;
    Some(Stamp {
        mtime: meta.modified().ok()?,
        len: meta.len(),
    })
}

