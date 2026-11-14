use std::path::{Path, PathBuf};
use std::sync::OnceLock;

pub struct Row {
    pub rule: bool,
    pub section: String,
    pub block: String,
    pub name: String,
    pub arg: String,
    pub id: String,
}

static PAGE: OnceLock<PathBuf> = OnceLock::new();

pub fn set_page(path: &str) {
    let _ = PAGE.set(PathBuf::from(path));
}

fn folder(start: &Path, kind: &str) -> Option<PathBuf> {
    for dir in start.ancestors() {
        let f = dir.join(".notation").join(kind);
        if f.is_dir() {
            return Some(f);
        }
    }
    None
}

fn starts() -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Ok(d) = std::env::var("AIU_PAGE_DIR") {
        out.push(PathBuf::from(d));
    }
    if let Some(p) = PAGE.get() {
        if let Ok(c) = p.canonicalize() {
            if let Some(d) = c.parent() {
                out.push(d.to_path_buf());
            }
        }
    }
    if let Ok(d) = std::env::current_dir() {
        out.push(d);
    }
    out
}

fn tokens(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut in_str = false;
    let mut esc = false;
    for c in text.chars() {
        let n = c as u32;
        if in_str {
            if esc {
                if n == 110 {
                    cur.push(10 as char);
                } else {
                    cur.push(c);
                }
                esc = false;
            } else if n == 92 {
                esc = true;
            } else if n == 34 {
                in_str = false;
                out.push(std::mem::take(&mut cur));
            } else {
                cur.push(c);
            }
        } else if n == 34 {
            in_str = true;
        } else if n == 40 || n == 41 || c.is_whitespace() {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
        } else {
            cur.push(c);
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn row(t: &[String]) -> Option<Row> {
    let g = |i: usize| t.get(i).cloned().unwrap_or_default();
    match t.first().map(|s| s.as_str()) {
        Some("rule") => Some(Row {
            rule: true,
            section: g(1),
            block: g(2),
            name: g(3),
            arg: g(4),
            id: String::new(),
        }),
        Some("question") => Some(Row {
            rule: false,
            section: g(1),
            block: g(2),
            name: String::new(),
            arg: g(3),
            id: g(4),
        }),
        _ => None,
    }
}

pub fn read(kind: &str) -> Option<Vec<Row>> {
    let dir = starts().iter().find_map(|s| folder(s, kind))?;
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map_or(false, |x| x == "rktd"))
        .collect();
    files.sort();
    let mut rows = Vec::new();
    for f in files {
        if let Ok(text) = std::fs::read_to_string(&f) {
            if let Some(r) = row(&tokens(&text)) {
                rows.push(r);
            }
        }
    }
    Some(rows)
}
