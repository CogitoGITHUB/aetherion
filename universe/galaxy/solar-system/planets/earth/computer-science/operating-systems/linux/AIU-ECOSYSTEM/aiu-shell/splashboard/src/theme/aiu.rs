use std::collections::HashMap;
use std::path::{Path, PathBuf};

fn dir() -> Option<PathBuf> {
    if let Ok(d) = std::env::var("AIU_THEME_DIR") {
        let p = PathBuf::from(d);
        if p.is_dir() { return Some(p); }
    }
    let h = std::env::var("HOME").ok()?;
    let f = Path::new(&h).join(".config/aiu/theme-dir");
    let d = std::fs::read_to_string(f).ok()?;
    let p = PathBuf::from(d.trim());
    if p.is_dir() { Some(p) } else { None }
}

fn roles() -> Option<HashMap<String, String>> {
    let d = dir()?;
    let n = std::fs::read_to_string(d.join("active")).ok()?;
    let n = n.trim();
    if n.is_empty() { return None; }
    if !n.chars().all(|c| c.is_ascii_alphanumeric() || "-_".contains(c)) { return None; }
    let s = std::fs::read_to_string(d.join(format!("{n}.theme"))).ok()?;
    let mut m = HashMap::new();
    for l in s.lines() {
        if let Some((k, v)) = l.split_once("=") {
            m.insert(k.trim().to_string(), v.trim().to_string());
        }
    }
    Some(m)
}

fn get(m: &HashMap<String, String>, r: &str) -> String {
    match m.get(r) {
        Some(v) => v.clone(),
        None => match r {
            "text" => "white",
            "dim" => "#6e6e6e",
            "error" => "red",
            _ => "none",
        }.to_string(),
    }
}

fn hex_ok(v: &str) -> bool {
    !v.starts_with("#")
        || (v.len() == 7 && v[1..].chars().all(|x| x.is_ascii_hexdigit()))
}

use super::Theme;
use ratatui::style::Color;

fn col(v: &str) -> Color {
    if v == "none" || !hex_ok(v) { return Color::Reset; }
    if v == "gray" { return Color::DarkGray; }
    v.parse().unwrap_or(Color::Reset)
}

pub fn apply(mut t: Theme) -> Theme {
    let Some(m) = roles() else { return t };
    let tx = col(&get(&m, "text"));
    let dm = col(&get(&m, "dim"));
    let er = col(&get(&m, "error"));
    let bg = col(&get(&m, "bg"));
    t.bg = bg;
    t.bg_subtle = bg;
    t.text = tx;
    t.text_secondary = tx;
    t.panel_title = tx;
    t.status_ok = tx;
    t.status_warn = tx;
    t.accent_today = tx;
    t.accent_event = tx;
    t.text_dim = dm;
    t.panel_border = dm;
    t.status_error = er;
    t.palette_series = vec![tx, dm];
    t.palette_heatmap = vec![dm, dm, dm, tx, tx];
    t
}
