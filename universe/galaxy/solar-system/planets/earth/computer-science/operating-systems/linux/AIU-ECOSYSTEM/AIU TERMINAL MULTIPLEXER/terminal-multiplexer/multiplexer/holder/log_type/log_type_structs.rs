use super::*;

/// LIMIT_BYTES is the size one session's log may reach before it is trimmed:
/// four mebibytes, which is a long run's worth of a busy pane on this phone.
pub const LIMIT_BYTES: u64 = 4 * 1024 * 1024;

/// KEEP_RECORDS is how many of the newest records a trim keeps. It is small
/// enough that the kept part is far under the limit, and large enough that the
/// panes' recent words, the last command records and the state a client reads
/// at attach are all still there.
pub const KEEP_RECORDS: usize = 2000;

/// Trimmed is what one trim did: the rule's own numbers, so the holder can
/// write them down as a record.
#[derive(Clone, Debug)]
pub struct Trimmed {
    /// dropped is how many records the trim let go.
    pub dropped: usize,
    /// kept is how many records the log holds now.
    pub kept: usize,
    /// from is the seq of the first record kept, and to the last one let go.
    pub from: u64,
    pub to: u64,
    /// limit is the rule that was applied, in bytes.
    pub limit: u64,
}

/// Log is one session's append-only log file.
pub struct Log {
    pub(crate) path: PathBuf,
    pub(crate) file: std::fs::File,
    /// bytes is how much the file holds, so the bound is checked without a
    /// stat on every record.
    pub(crate) bytes: u64,
    /// limit and keep are the rule in force for this log.
    pub(crate) limit: u64,
    pub(crate) keep: usize,
    /// tripped says a trim already failed: the rule is broken and said once,
    /// and the log does not try again on every record that follows.
    pub(crate) tripped: bool,
}

