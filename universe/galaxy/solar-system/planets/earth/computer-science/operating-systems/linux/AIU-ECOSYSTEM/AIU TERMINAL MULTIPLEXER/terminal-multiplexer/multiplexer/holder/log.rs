// One job: the session's log — one JSON record per line, flushed per record,
// bounded by a written rule, and private to the owner.
//
// The log IS the record (rule 01): a holder that is killed leaves a readable
// prefix and never a torn record, because every record is written whole and
// flushed before the holder moves on (D-006).
//
// Two rules bound it (TODO item 51), and both live here because this file is
// where they are kept:
//
//   - One session's log stays at or under `limit` bytes. When it passes that,
//     it is trimmed in ONE rewrite — a new file, synced, renamed over the old —
//     to the newest `keep` records, and only to as many of them as fit in half
//     the bound, so neither the count nor the size can make the other useless.
//     A reader never sees half a record and never loses the newest ones. The trim is the holder's to record: this
//     file answers what was dropped and what was kept, and the holder writes
//     that as a record of its own, so a reader asking for a seq the journal no
//     longer holds is told so instead of quietly getting less.
//   - Every file and directory of the session is the owner's alone: the state
//     directory is 0700 and the files in it are 0600, set at creation AND at
//     open, because a file made before this rule was written was 0644.

use std::fs::OpenOptions;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[path = "log_type/log_type_structs.rs"]
mod log_type_structs;
pub(crate) use log_type_structs::*;
#[path = "log_type/log_type_methods.rs"]
mod log_type_methods;
#[path = "log_file/log_file_paths.rs"]
mod log_file_paths;
pub(crate) use log_file_paths::*;
#[cfg(test)]
#[path = "log_test/log_test_rotation.rs"]
mod tests;
