use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

struct Roles {
    dim: String,
    error: String,
}

static ROLES: OnceLock<Roles> = OnceLock::new();

fn theme_dir() -> Option<PathBuf> {
    if let Ok(d) = std::env::var("AIU_THEME_DIR") {
        let p = PathBuf::from(d);
        if p.is_dir() {
            return Some(p);
        }
    }
    let home = std::env::var("HOME").ok()?;
    let f = PathBuf::from(home).join(".config").join("aiu").join("theme-dir");
    let d = fs::read_to_string(f).ok()?;
    let p = PathBuf::from(d.trim());
    if p.is_dir() { Some(p) } else { None }
}

fn name_ok(n: &str) -> bool {
    !n.is_empty() && n.bytes().all(|b| b.is_ascii_alphanumeric() || b == 45 || b == 95)
}

fn value_code(v: &str) -> Option<String> {
    if v == "none" {
        return Some(String::new());
    }
    if v.len() == 7 && v.starts_with("#") {
        let r = u8::from_str_radix(v.get(1..3)?, 16).ok()?;
        let g = u8::from_str_radix(v.get(3..5)?, 16).ok()?;
        let b = u8::from_str_radix(v.get(5..7)?, 16).ok()?;
        return Some(format!("\x1b[38;2;{};{};{}m", r, g, b));
    }
    let n = match v {
        "black" => 30, "red" => 31, "green" => 32, "yellow" => 33,
        "blue" => 34, "magenta" => 35, "cyan" => 36, "white" => 97,
        "gray" | "grey" => 90,
        _ => return None,
    };
    Some(format!("\x1b[{}m", n))
}

fn load() -> Roles {
    let mut dim = value_code("#6e6e6e").unwrap_or_default();
    let mut error = value_code("red").unwrap_or_default();
    let body = theme_dir().and_then(|d| {
        let name = fs::read_to_string(d.join("active")).ok()?;
        let name = name.trim().to_string();
        if !name_ok(&name) {
            return None;
        }
        fs::read_to_string(d.join(format!("{}.theme", name))).ok()
    });
    if let Some(text) = body {
        for l in text.lines() {
            if let Some((k, v)) = l.split_once("=") {
                if let Some(c) = value_code(v.trim()) {
                    match k.trim() {
                        "dim" => dim = c,
                        "error" => error = c,
                        _ => {}
                    }
                }
            }
        }
    }
    Roles { dim, error }
}

pub fn paint(codes: &[u32], s: &str) -> String {
    let r = ROLES.get_or_init(load);
    let mut styles: Vec<String> = Vec::new();
    let mut colour = String::new();
    for c in codes {
        if *c < 30 {
            styles.push(c.to_string());
        } else if *c == 31 {
            colour = r.error.clone();
        } else if *c == 90 {
            colour = r.dim.clone();
        }
    }
    let mut out = String::new();
    if !styles.is_empty() {
        out.push_str(&format!("\x1b[{}m", styles.join(";")));
    }
    out.push_str(&colour);
    if out.is_empty() {
        return s.to_string();
    }
    out.push_str(s);
    out.push_str("\x1b[0m");
    out
}
