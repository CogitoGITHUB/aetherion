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

use super::{Color, Theme};

fn c(v: &str) -> Option<Color> {
    let v = if v == "gray" { "bright-black" } else { v };
    if !hex_ok(v) { return None; }
    Color::from_str(v)
}

pub fn apply(mut t: Theme) -> Theme {
    let Some(m) = roles() else { return t };
    let tx = c(&get(&m, "text"));
    let dm = c(&get(&m, "dim"));
    t.background = c(&get(&m, "bg"));
    if let Some(x) = tx {
        t.text_fg = x.clone();
        t.input_text_fg = x.clone();
        t.result_count_fg = x.clone();
        t.result_name_fg = x.clone();
        t.result_value_fg = x.clone();
        t.match_fg = x.clone();
        t.preview_title_fg = x.clone();
        t.selection_bg = x.clone();
        t.channel_mode_bg = x.clone();
        t.remote_control_mode_bg = x.clone();
        t.action_picker_mode_bg = x.clone();
    }
    if let Some(x) = dm {
        t.border_fg = x.clone();
        t.dimmed_text_fg = x.clone();
        t.result_line_number_fg = x.clone();
    }
    t
}
