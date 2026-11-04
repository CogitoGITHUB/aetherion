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
    path: PathBuf,
    file: std::fs::File,
    /// bytes is how much the file holds, so the bound is checked without a
    /// stat on every record.
    bytes: u64,
    /// limit and keep are the rule in force for this log.
    limit: u64,
    keep: usize,
    /// tripped says a trim already failed: the rule is broken and said once,
    /// and the log does not try again on every record that follows.
    tripped: bool,
}

impl Log {
    /// open opens the log with the rule this program ships, for a session.
    pub fn open(path: &Path) -> Result<Log, String> {
        Log::open_with(path, LIMIT_BYTES, KEEP_RECORDS)
    }

    /// open_with opens the log with a rule of the caller's choosing: the
    /// session uses the shipped one, and a probe or a small disk may say less.
    pub fn open_with(path: &Path, limit: u64, keep: usize) -> Result<Log, String> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .mode(0o600)
            .open(path)
            .map_err(|why| format!("the log {} cannot be opened: {}", path.display(), why))?;
        // A file made before the rule was written is 0644: it is made private
        // here, and a refusal is named rather than passed over.
        private_file(path)?;
        let bytes = file
            .metadata()
            .map_err(|why| format!("the log {} cannot be measured: {}", path.display(), why))?
            .len();
        Ok(Log {
            path: path.to_path_buf(),
            file,
            bytes,
            limit,
            keep: keep.max(1),
            tripped: false,
        })
    }

    /// append writes one record as one line and flushes it, so the record is
    /// on disk before the holder does anything else.
    pub fn append(&mut self, record: &serde_json::Value) -> Result<(), String> {
        let mut line = record.to_string();
        line.push('\n');
        self.file
            .write_all(line.as_bytes())
            .map_err(|why| format!("the record cannot be written to the log: {}", why))?;
        self.file
            .flush()
            .map_err(|why| format!("the record cannot be flushed to the log: {}", why))?;
        self.bytes += line.len() as u64;
        Ok(())
    }

    /// over_limit answers whether the rule says the log must be trimmed now.
    pub fn over_limit(&self) -> bool {
        self.bytes > self.limit && !self.tripped
    }

    /// size answers how many bytes the log holds now.
    pub fn size(&self) -> u64 {
        self.bytes
    }

    /// rule answers the bound in force, so the holder can say it in its own
    /// records without a second copy of the numbers.
    pub fn rule(&self) -> (u64, usize) {
        (self.limit, self.keep)
    }

    /// trim rewrites the log to its newest records, and answers what it did.
    ///
    /// The rewrite never edits the file in place: the kept part is written to
    /// a sibling, synced, and renamed over the log. A reader that opens the log
    /// while this runs reads the old one whole or the new one whole, and a
    /// holder killed in the middle leaves the old log untouched.
    ///
    /// The count and the size are both kept, and neither is allowed to make the
    /// other useless: at most `keep` records are kept, and only as many of them
    /// as fit in half the bound. A trim that could not get under the bound —
    /// one record bigger than half of it — is refused by name, and the log does
    /// not try again on every record after it.
    pub fn trim(&mut self) -> Result<Trimmed, String> {
        let body = std::fs::read_to_string(&self.path).map_err(|why| {
            format!(
                "the log {} cannot be read for its trim: {}",
                self.path.display(),
                why
            )
        })?;
        let held: Vec<&str> = body.lines().filter(|line| !line.trim().is_empty()).collect();
        let total = held.len();
        let budget = self.limit / 2;
        let mut kept_len: usize = 0;
        let mut used: u64 = 0;
        for line in held.iter().rev() {
            let size = line.len() as u64 + 1;
            if kept_len > 0 && (used + size > budget || kept_len >= self.keep) {
                break;
            }
            used += size;
            kept_len += 1;
        }
        let from_at = total - kept_len;
        let kept = &held[from_at..];
        let dropped = from_at;
        let from = kept.first().map(|line| seq_of(line)).unwrap_or(0);
        let to = held
            .get(from_at.wrapping_sub(1))
            .map(|line| seq_of(line))
            .unwrap_or(0);
        if used > self.limit {
            // One record is bigger than the bound: the rule cannot be kept by
            // trimming, and saying so once is better than a trim per record.
            self.tripped = true;
            return Err(format!(
                "one record is {} bytes, and the bound is {}: the journal cannot be \
                 trimmed under it",
                used, self.limit
            ));
        }
        let mut text = String::new();
        for line in kept {
            text.push_str(line);
            text.push('\n');
        }
        let beside = self.path.with_extension("log.new");
        let mut fresh = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .mode(0o600)
            .open(&beside)
            .map_err(|why| {
                format!(
                    "the trimmed log {} cannot be made: {}",
                    beside.display(),
                    why
                )
            })?;
        fresh
            .write_all(text.as_bytes())
            .and_then(|_| fresh.sync_all())
            .map_err(|why| {
                let _ = std::fs::remove_file(&beside);
                self.tripped = true;
                format!("the trimmed log cannot be written: {}", why)
            })?;
        drop(fresh);
        std::fs::rename(&beside, &self.path).map_err(|why| {
            let _ = std::fs::remove_file(&beside);
            self.tripped = true;
            format!(
                "the trimmed log {} cannot be put in place: {}",
                self.path.display(),
                why
            )
        })?;
        // The handle holds the old file, which the rename left behind: it is
        // opened again, and the rule's own count starts from the new size.
        self.file = OpenOptions::new()
            .append(true)
            .open(&self.path)
            .map_err(|why| {
                self.tripped = true;
                format!(
                    "the trimmed log {} cannot be opened again: {}",
                    self.path.display(),
                    why
                )
            })?;
        self.bytes = std::fs::metadata(&self.path)
            .map(|meta| meta.len())
            .unwrap_or(text.len() as u64);
        private_file(&self.path)?;
        Ok(Trimmed {
            dropped,
            kept: kept.len(),
            from,
            to,
            limit: self.limit,
        })
    }

    /// records answers every record the log file holds, oldest first, read
    /// back from the file: what the log says is what the file holds.
    pub fn records(path: &Path) -> Result<Vec<serde_json::Value>, String> {
        let body = std::fs::read_to_string(path)
            .map_err(|why| format!("the log {} cannot be read: {}", path.display(), why))?;
        let mut held: Vec<serde_json::Value> = Vec::new();
        for line in body.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            match serde_json::from_str::<serde_json::Value>(trimmed) {
                Ok(value) => held.push(value),
                Err(why) => {
                    return Err(format!(
                        "the log holds a line that is not a record: {}",
                        why
                    ))
                }
            }
        }
        Ok(held)
    }
}

/// seq_of answers the seq a record line carries, and 0 when it carries none:
/// the trim needs the numbers only to say what it let go.
fn seq_of(line: &str) -> u64 {
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

#[cfg(test)]
mod tests {
    use super::*;

    /// a_scratch is a directory of this test's own, emptied first.
    fn a_scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-log-{}-{}", std::process::id(), name));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    /// a_record is one record with the seq the caller names.
    fn a_record(seq: u64, text: &str) -> serde_json::Value {
        serde_json::json!({ "seq": seq, "kind": "progress", "outputs": { "text": text } })
    }

    #[test]
    fn a_log_is_the_owners_alone() {
        let dir = a_scratch("private");
        let path = dir.join("events.log");
        let mut log = Log::open(&path).unwrap();
        log.append(&a_record(1, "one")).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "the log is 0600: {:o}", mode);
    }

    #[test]
    fn a_state_directory_is_the_owners_alone() {
        let dir = a_scratch("dir").join("session");
        private_dir(&dir).unwrap();
        let mode = std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700, "the directory is 0700: {:o}", mode);
    }

    #[test]
    fn a_loose_file_is_made_private_when_the_log_opens_it() {
        let dir = a_scratch("loose");
        let path = dir.join("events.log");
        std::fs::write(&path, "").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        let _log = Log::open(&path).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "the old file is made private: {:o}", mode);
    }

    #[test]
    fn the_rule_trims_to_the_newest_records_and_says_what_it_let_go() {
        let dir = a_scratch("trim");
        let path = dir.join("events.log");
        // A limit of 260 with 10 records of 49 bytes: half the bound is 130,
        // so two records are kept even though the count would take three.
        let mut log = Log::open_with(&path, 260, 3).unwrap();
        for seq in 1..=10 {
            log.append(&a_record(seq, "x")).unwrap();
        }
        assert!(log.over_limit(), "ten records pass a limit of 260 bytes");
        let trimmed = log.trim().unwrap();
        assert_eq!(trimmed.dropped, 8, "eight are let go");
        assert_eq!(trimmed.kept, 2, "two are kept: the bound, not the count, decides");
        assert_eq!(trimmed.from, 9, "the kept part starts at seq 9");
        assert_eq!(trimmed.to, 8, "and the let-go part ends at seq 8");
        let held = Log::records(&path).unwrap();
        assert_eq!(held.len(), 2, "the file holds two records");
        assert_eq!(held.first().unwrap()["seq"], 9, "the newest two");
        assert_eq!(held.last().unwrap()["seq"], 10);
        assert!(!log.over_limit(), "the trimmed log is under the rule again");
    }

    #[test]
    fn a_trim_writes_no_half_record_and_no_second_file_is_left() {
        let dir = a_scratch("whole");
        let path = dir.join("events.log");
        let mut log = Log::open_with(&path, 200, 10).unwrap();
        for seq in 1..=6 {
            log.append(&a_record(seq, "one line")).unwrap();
        }
        log.trim().unwrap();
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.ends_with('\n'), "the last record is whole");
        for line in body.lines() {
            assert!(
                serde_json::from_str::<serde_json::Value>(line).is_ok(),
                "every line is a record: {:?}",
                line
            );
        }
        assert!(
            !path.with_extension("log.new").exists(),
            "the file beside the log is gone"
        );
    }

    #[test]
    fn one_record_bigger_than_the_bound_is_refused_and_not_retried() {
        let dir = a_scratch("huge");
        let path = dir.join("events.log");
        let mut log = Log::open_with(&path, 40, 2).unwrap();
        log.append(&a_record(1, "x")).unwrap();
        assert!(log.over_limit(), "one record of 49 bytes passes a bound of 40");
        let why = log.trim().unwrap_err();
        assert!(
            why.contains("cannot be trimmed under it"),
            "the refusal names the rule: {:?}",
            why
        );
        assert!(!log.over_limit(), "the rule is said once and not retried");
        assert_eq!(Log::records(&path).unwrap().len(), 1, "nothing was lost");
    }

    #[test]
    fn a_session_log_under_the_rule_is_never_trimmed() {
        let dir = a_scratch("under");
        let path = dir.join("events.log");
        let mut log = Log::open(&path).unwrap();
        for seq in 1..=50 {
            log.append(&a_record(seq, "a short line")).unwrap();
        }
        assert!(!log.over_limit(), "fifty short records are far under 4 MiB");
        assert_eq!(Log::records(&path).unwrap().len(), 50, "every record is held");
        assert_eq!(log.rule().0, LIMIT_BYTES, "the shipped rule is the one in force");
    }
}
