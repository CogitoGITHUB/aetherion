use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

const FULL_ROWS: usize = 16;

struct Slot {
    key: (PathBuf, usize),
    at: Instant,
    runs: u8,
    lines: Vec<String>,
}

static GIT_OPEN: AtomicBool = AtomicBool::new(false);
static HOME_OPEN: AtomicBool = AtomicBool::new(false);
static GIT: Mutex<Option<Slot>> = Mutex::new(None);
static HOME: Mutex<Option<Slot>> = Mutex::new(None);

pub fn toggle_git() {
    GIT_OPEN.fetch_xor(true, Ordering::Relaxed);
}

pub fn toggle_home() {
    HOME_OPEN.fetch_xor(true, Ordering::Relaxed);
}

fn binary() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home)
        .join(".local/share/aiu-pm/prefix/aiu-splash/current/bin/aiu-splash")
}

fn in_git() -> bool {
    match Command::new("git")
        .args(["rev-parse", "--is-inside-work-tree"])
        .output()
    {
        Ok(out) => out.status.success(),
        Err(_) => false,
    }
}

fn dump(which: &str, width: usize) -> Vec<String> {
    let bin = binary();
    if !bin.exists() {
        return Vec::new();
    }
    if which == "project" && !in_git() {
        return Vec::new();
    }
    let out = Command::new(bin)
        .args(["dump", which, &width.to_string()])
        .output();
    let text = match out {
        Ok(o) if o.status.success() => {
            String::from_utf8_lossy(&o.stdout).to_string()
        }
        _ => return Vec::new(),
    };
    let mut lines: Vec<String> =
        text.lines().map(|l| l.trim_end().to_string()).collect();
    while lines.last().map_or(false, |l| l.is_empty()) {
        lines.pop();
    }
    while lines.first().map_or(false, |l| l.is_empty()) {
        lines.remove(0);
    }
    lines
}

fn load(
    slot: &Mutex<Option<Slot>>,
    which: &str,
    width: usize,
    per_dir: bool,
) -> Vec<String> {
    let cwd = if per_dir {
        std::env::current_dir().unwrap_or_default()
    } else {
        PathBuf::new()
    };
    let key = (cwd, width);
    let mut guard = match slot.lock() {
        Ok(g) => g,
        Err(_) => return Vec::new(),
    };
    let same = guard.as_ref().map_or(false, |s| s.key == key);
    let redo = match guard.as_ref() {
        Some(s) if same => {
            s.runs < 2 && s.at.elapsed() > Duration::from_secs(4)
        }
        _ => true,
    };
    if redo {
        let runs = match guard.as_ref() {
            Some(s) if same => s.runs + 1,
            _ => 1,
        };
        let lines = dump(which, width);
        *guard = Some(Slot { key, at: Instant::now(), runs, lines });
    }
    guard.as_ref().map(|s| s.lines.clone()).unwrap_or_default()
}

fn pick_raw(lines: Vec<String>, open: bool) -> Vec<String> {
    if open {
        lines.into_iter().take(FULL_ROWS).collect()
    } else {
        one_line(lines)
    }
}

pub fn git_text(width: usize) -> Vec<String> {
    let lines = load(&GIT, "project", width, true);
    pick(lines, GIT_OPEN.load(Ordering::Relaxed))
}

pub fn home_text(width: usize) -> Vec<String> {
    let lines = load(&HOME, "home", width, false);
    pick(lines, HOME_OPEN.load(Ordering::Relaxed))
}

fn one_line(lines: Vec<String>) -> Vec<String> {
    let art = |c: char| {
        let n = c as u32;
        (0x2500..=0x259F).contains(&n) || n == 0x26A0
    };
    for l in &lines {
        let digit = l.chars().any(|c| c.is_ascii_digit());
        if digit && !l.chars().any(art) {
            return vec![l.trim().to_string()];
        }
    }
    lines.into_iter().take(1).collect()
}

fn pick(lines: Vec<String>, open: bool) -> Vec<String> {
    let _ = open;
    pick_raw(drop_warnings(lines), false)
}

fn is_warn(l: &str) -> bool {
    l.contains("\u{26A0}") || l.contains("splashboard/logs")
}

fn drop_warnings(lines: Vec<String>) -> Vec<String> {
    let warn: Vec<bool> = lines.iter().map(|l| is_warn(l)).collect();
    let mut out: Vec<String> = Vec::new();
    for (i, l) in lines.iter().enumerate() {
        let next_warn = i + 1 >= lines.len() || warn[i + 1];
        let rule = l.trim_start().starts_with("\u{2500}");
        if warn[i] || (rule && next_warn) {
            continue;
        }
        let blank = l.trim().is_empty();
        let prev_blank = out.last().map_or(true, |p| p.trim().is_empty());
        if blank && prev_blank {
            continue;
        }
        out.push(l.clone());
    }
    while out.last().map_or(false, |p| p.trim().is_empty()) {
        out.pop();
    }
    out
}

static OFFSET: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);

pub fn overlay_open() -> bool {
    GIT_OPEN.load(Ordering::Relaxed) || HOME_OPEN.load(Ordering::Relaxed)
}

pub fn close_all() {
    GIT_OPEN.store(false, Ordering::Relaxed);
    HOME_OPEN.store(false, Ordering::Relaxed);
    OFFSET.store(0, Ordering::Relaxed);
}

pub fn scroll(delta: isize) {
    let now = OFFSET.load(Ordering::Relaxed) as isize;
    OFFSET.store((now + delta).max(0) as usize, Ordering::Relaxed);
}

pub fn offset() -> usize {
    OFFSET.load(Ordering::Relaxed)
}

pub fn set_offset(n: usize) {
    OFFSET.store(n, Ordering::Relaxed);
}

pub fn overlay(width: usize) -> Option<(String, Vec<String>)> {
    if GIT_OPEN.load(Ordering::Relaxed) {
        let lines = load(&GIT, "project", width, true);
        return Some((String::from("aiu git"), drop_warnings(lines)));
    }
    if HOME_OPEN.load(Ordering::Relaxed) {
        let lines = load(&HOME, "home", width, false);
        return Some((String::from("aiu home"), drop_warnings(lines)));
    }
    None
}
