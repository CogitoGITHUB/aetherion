use super::*;

impl Log {
    #[allow(dead_code)]
    pub fn open(path: &Path) -> Result<Log, String> {
        Log::open_with(path, LIMIT_BYTES, KEEP_RECORDS)
    }

    pub fn open_with(path: &Path, limit: u64, keep: usize) -> Result<Log, String> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .mode(0o600)
            .open(path)
            .map_err(|why| format!("the log {} cannot be opened: {}", path.display(), why))?;
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

    pub fn over_limit(&self) -> bool {
        self.bytes > self.limit && !self.tripped
    }

    pub fn size(&self) -> u64 {
        self.bytes
    }

    pub fn rule(&self) -> (u64, usize) {
        (self.limit, self.keep)
    }

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

