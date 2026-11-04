use super::*;

pub const LIMIT_BYTES: u64 = 4 * 1024 * 1024;

pub const KEEP_RECORDS: usize = 2000;

#[derive(Clone, Debug)]
pub struct Trimmed {
    pub dropped: usize,
    pub kept: usize,
    pub from: u64,
    pub to: u64,
    pub limit: u64,
}

pub struct Log {
    pub(crate) path: PathBuf,
    pub(crate) file: std::fs::File,
    pub(crate) bytes: u64,
    pub(crate) limit: u64,
    pub(crate) keep: usize,
    pub(crate) tripped: bool,
}

