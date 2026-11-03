
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};

pub fn append_record(path: &str, record: &str) -> usize {
    let mut file = match OpenOptions::new().create(true).append(true).open(path) {
        Ok(open) => open,
        Err(why) => panic!("the journal cannot be opened: {}", why),
    };
    if let Err(why) = writeln!(file, "{}", record) {
        panic!("the journal cannot be written: {}", why);
    }
    if let Err(why) = file.flush() {
        panic!("the journal cannot be flushed: {}", why);
    }
    records(path).len()
}

pub fn records(path: &str) -> Vec<String> {
    let mut file = match File::open(path) {
        Ok(open) => open,
        Err(_) => return Vec::new(),
    };
    let mut text = String::new();
    if file.read_to_string(&mut text).is_err() {
        return Vec::new();
    }
    text.lines().map(|line| line.to_string()).collect()
}

pub fn archive(path: &str, saved_before: &str) {
    let records = records(path);
    if records.is_empty() {
        return;
    }
    let base = format!("{}.base", path);
    if !std::path::Path::new(&base).exists() {
        let _ = std::fs::write(&base, saved_before);
    }
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(format!("{}.history", path)) {
        for record in records {
            let _ = writeln!(file, "{}", record);
        }
    }
}

pub fn clear(path: &str) {
    let _ = std::fs::write(path, "");
}

/// comes back exactly. A record the replay does not know is skipped: the
pub fn replay(text: &str, records: &[String]) -> String {
    let mut grown = text.to_string();
    for record in records {
        if let Some((at, more)) = insert_at_text(record) {
            grown.insert_str(at.min(grown.len()), &more);
        } else if let Some((at, count)) = delete_at_text(record) {
            let to = at.saturating_add(count).min(grown.len());
            let at = at.min(grown.len());
            grown = format!("{}{}", &grown[..at], &grown[to..]);
        } else if let Some(more) = insert_text(record) {
            grown.push_str(&more);
        }
    }
    grown
}

fn insert_text(record: &str) -> Option<String> {
    let rest = record.strip_prefix("insert ")?;
    Some(unescape(rest))
}

fn insert_at_text(record: &str) -> Option<(usize, String)> {
    let rest = record.strip_prefix("insert-at ")?;
    let (at, text) = rest.split_once(' ')?;
    Some((at.parse().ok()?, unescape(text)))
}

fn delete_at_text(record: &str) -> Option<(usize, usize)> {
    let rest = record.strip_prefix("delete-at ")?;
    let (at, count) = rest.split_once(' ')?;
    Some((at.parse().ok()?, count.parse().ok()?))
}

pub fn escape(text: &str) -> String {
    let mut out = String::new();
    for c in text.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            _ => out.push(c),
        }
    }
    out
}

pub fn unescape(text: &str) -> String {
    let mut out = String::new();
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('n') => out.push('\n'),
                Some('t') => out.push('\t'),
                Some('r') => out.push('\r'),
                Some('\\') => out.push('\\'),
                Some(other) => {
                    out.push('\\');
                    out.push(other);
                }
                None => out.push('\\'),
            }
        } else {
            out.push(c);
        }
    }
    out
}
