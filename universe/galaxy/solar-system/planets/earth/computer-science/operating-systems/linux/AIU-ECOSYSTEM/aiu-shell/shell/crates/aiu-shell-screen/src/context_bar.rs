use clap::Parser;
use starship::context::{Context, Properties, Target};
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

static CACHE: Mutex<Option<(PathBuf, Instant, Vec<String>)>> =
    Mutex::new(None);

const MODULES: [&str; 5] =
    ["git_branch", "git_status", "rust", "python", "nodejs"];

fn tidy(text: &str) -> String {
    let mut out = String::new();
    let mut skip = false;
    for ch in text.chars() {
        let code = ch as u32;
        if skip {
            if ch.is_ascii_alphabetic() {
                skip = false;
            }
        } else if code == 27 {
            skip = true;
        } else if code >= 0xE000 && code <= 0xF8FF {
            continue;
        } else if code >= 32 {
            out.push(ch);
        }
    }
    let mut s = out.trim().to_string();
    for lead in ["on ", "via ", "is ", "took "] {
        let next = s.strip_prefix(lead).map(|r| r.trim().to_string());
        if let Some(n) = next {
            s = n;
        }
    }
    s
}

fn compute() -> Vec<String> {
    let props = match Properties::try_parse_from(["starship"]) {
        Ok(p) => p,
        Err(_) => return Vec::new(),
    };
    let ctx = Context::new(props, Target::Main);
    let mut parts = Vec::new();
    for name in MODULES {
        if let Some(raw) = starship::print::get_module(name, &ctx) {
            let t = tidy(&raw);
            if !t.is_empty() {
                parts.push(t);
            }
        }
    }
    parts
}

pub fn parts() -> Vec<String> {
    let cwd = std::env::current_dir().unwrap_or_default();
    if let Ok(guard) = CACHE.lock() {
        if let Some((dir, at, saved)) = guard.as_ref() {
            if *dir == cwd && at.elapsed() < Duration::from_secs(3) {
                return saved.clone();
            }
        }
    }
    let fresh = std::panic::catch_unwind(compute).unwrap_or_default();
    if let Ok(mut guard) = CACHE.lock() {
        *guard = Some((cwd, Instant::now(), fresh.clone()));
    }
    fresh
}
