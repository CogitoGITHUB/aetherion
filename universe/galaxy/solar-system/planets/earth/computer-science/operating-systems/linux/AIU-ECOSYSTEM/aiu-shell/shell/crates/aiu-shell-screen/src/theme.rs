use ratatui::style::Color;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Instant;

#[derive(Clone, Copy)]
struct Val {
    color: Color,
    rgb: (f32, f32, f32),
}

#[derive(Clone, Copy)]
struct Roles {
    text: Val,
    dim: Val,
    error: Val,
}

static STATE: Mutex<Option<(Instant, Roles)>> = Mutex::new(None);

fn theme_dir() -> Option<PathBuf> {
    if let Ok(d) = std::env::var("AIU_THEME_DIR") {
        let p = PathBuf::from(d);
        if p.is_dir() {
            return Some(p);
        }
    }
    let home = std::env::var("HOME").ok()?;
    let f = PathBuf::from(home)
        .join(".config").join("aiu").join("theme-dir");
    let d = fs::read_to_string(f).ok()?;
    let p = PathBuf::from(d.trim());
    if p.is_dir() { Some(p) } else { None }
}

fn parse(v: &str) -> Option<Val> {
    if v == "none" {
        return Some(Val { color: Color::Reset,
            rgb: (255.0, 255.0, 255.0) });
    }
    if v.len() == 7 && v.starts_with("#") {
        let r = u8::from_str_radix(v.get(1..3)?, 16).ok()?;
        let g = u8::from_str_radix(v.get(3..5)?, 16).ok()?;
        let b = u8::from_str_radix(v.get(5..7)?, 16).ok()?;
        return Some(Val { color: Color::Rgb(r, g, b),
            rgb: (r as f32, g as f32, b as f32) });
    }
    let (c, r) = match v {
        "black" => (Color::Black, (0.0, 0.0, 0.0)),
        "red" => (Color::Red, (220.0, 40.0, 40.0)),
        "green" => (Color::Green, (40.0, 200.0, 40.0)),
        "yellow" => (Color::Yellow, (220.0, 200.0, 40.0)),
        "blue" => (Color::Blue, (60.0, 80.0, 220.0)),
        "magenta" => (Color::Magenta, (200.0, 60.0, 200.0)),
        "cyan" => (Color::Cyan, (40.0, 200.0, 200.0)),
        "white" => (Color::White, (255.0, 255.0, 255.0)),
        "gray" | "grey" => (Color::DarkGray, (110.0, 110.0, 110.0)),
        _ => return None,
    };
    Some(Val { color: c, rgb: r })
}

fn load() -> Roles {
    let mut r = Roles {
        text: parse("white").unwrap(),
        dim: parse("#6e6e6e").unwrap(),
        error: parse("red").unwrap(),
    };
    let body = theme_dir().and_then(|d| {
        let name = fs::read_to_string(d.join("active")).ok()?;
        let name = name.trim().to_string();
        let ok = !name.is_empty() && name.bytes().all(|b|
            b.is_ascii_alphanumeric() || b == 45 || b == 95);
        if !ok {
            return None;
        }
        fs::read_to_string(d.join(format!("{}.theme", name))).ok()
    });
    if let Some(text) = body {
        for l in text.lines() {
            if let Some((k, v)) = l.split_once("=") {
                if let Some(c) = parse(v.trim()) {
                    match k.trim() {
                        "text" => r.text = c,
                        "dim" => r.dim = c,
                        "error" => r.error = c,
                        _ => {}
                    }
                }
            }
        }
    }
    r
}

fn get(f: fn(&Roles) -> Val) -> Val {
    let mut g = STATE.lock().unwrap();
    let stale = match &*g {
        Some(_) => false,
        None => true,
    };
    if stale {
        *g = Some((Instant::now(), load()));
    }
    f(&g.as_ref().unwrap().1)
}

pub fn text() -> Color { get(|r| r.text).color }
pub fn dim() -> Color { get(|r| r.dim).color }
pub fn error() -> Color { get(|r| r.error).color }

pub fn rgb(role: &str) -> (f32, f32, f32) {
    match role {
        "dim" => get(|r| r.dim).rgb,
        "error" => get(|r| r.error).rgb,
        _ => get(|r| r.text).rgb,
    }
}

pub fn reload() {
    *STATE.lock().unwrap() = None;
}

pub fn dir() -> Option<PathBuf> {
    theme_dir()
}
