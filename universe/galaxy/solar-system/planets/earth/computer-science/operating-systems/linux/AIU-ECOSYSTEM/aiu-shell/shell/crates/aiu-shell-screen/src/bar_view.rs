use crate::input_state::{InputState, Mode};
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::widgets::{Clear, Paragraph};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static MENU_OPEN: AtomicBool = AtomicBool::new(false);
static CLOCK_CACHE: Mutex<(u64, String)> = Mutex::new((0, String::new()));

pub fn toggle_menu() {
    MENU_OPEN.fetch_xor(true, Ordering::Relaxed);
}

pub fn close_menu() {
    MENU_OPEN.store(false, Ordering::Relaxed);
}

fn menu_open() -> bool {
    MENU_OPEN.load(Ordering::Relaxed)
}

fn clock_text() -> String {
    let minute = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() / 60)
        .unwrap_or(0);
    let mut cache = match CLOCK_CACHE.lock() {
        Ok(guard) => guard,
        Err(_) => return String::new(),
    };
    if cache.1.is_empty() || cache.0 != minute {
        let shown = std::process::Command::new("date")
            .arg("+%H:%M  %Y-%m-%d")
            .stdin(std::process::Stdio::null())
            .output()
            .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
            .unwrap_or_default();
        *cache = (minute, shown);
    }
    cache.1.clone()
}

fn cut(text: &str, width: usize) -> String {
    text.chars().take(width).collect()
}

fn pad(text: &str, width: usize) -> String {
    let mut out = cut(text, width);
    let used = out.chars().count();
    out.push_str(&" ".repeat(width - used));
    out
}

fn edge_line(left: &str, right: &str, title: &str, width: usize) -> String {
    let head = cut(&format!("{}─┤ {} ├", left, title), width.saturating_sub(1));
    let fill = width.saturating_sub(head.chars().count() + 1);
    format!("{}{}{}", head, "─".repeat(fill), right)
}

fn rule_line(left: &str, right: &str, width: usize) -> String {
    format!("{}{}{}", left, "─".repeat(width.saturating_sub(2)), right)
}

fn body_line(text: &str, width: usize) -> String {
    let inner = width.saturating_sub(4).max(1);
    format!("│ {} │", pad(text, inner))
}

fn clock_rule_line(width: usize) -> String {
    let stamp = clock_text();
    let used = 8 + stamp.chars().count();
    if stamp.is_empty() || width < used + 6 {
        return rule_line("╰", "╯", width);
    }
    format!("╰{}┤ {} ├────╯", "─".repeat(width - 2 - used), stamp)
}

fn mode_label(state: &InputState) -> &str {
    match state.mode {
        Mode::Visual => "visual general",
        Mode::Insert => "insert",
        Mode::Search => "search",
    }
}

fn directory_path() -> String {
    std::env::current_dir()
        .map(|path| path.to_string_lossy().to_string())
        .unwrap_or_default()
}

fn directory_name() -> String {
    std::env::current_dir()
        .ok()
        .and_then(|path| path.file_name().map(|name| name.to_string_lossy().to_string()))
        .unwrap_or_default()
}

fn bar_rows(state: &InputState, width: usize) -> Vec<String> {
    let title = format!("{} [any] · {}", mode_label(state), directory_name());
    let hint = match state.mode {
        Mode::Visual => "trigger SPC  ·  press SPC for keys",
        Mode::Insert => "esc visual  enter run  up down history  ctrl+r search",
        Mode::Search => "type to filter  enter use  esc close",
    };
    vec![
        edge_line("╭", "╮", &title, width),
        body_line(hint, width),
        clock_rule_line(width),
    ]
}

fn tab_rows(width: usize) -> Vec<String> {
    let inner = width.saturating_sub(4).max(1);
    let chars: Vec<char> = directory_path().chars().collect();
    let mut rows: Vec<String> = chars.chunks(inner).map(|part| part.iter().collect()).collect();
    if rows.len() > 5 {
        let extra = rows.len() - 5;
        rows.drain(0..extra);
        let rest: String = rows[0].chars().skip(1).collect();
        rows[0] = format!("\u{2026}{}", rest);
    }
    let mut out = vec![edge_line("╭", "╮", "directory", width)];
    for row in rows {
        out.push(body_line(&row, width));
    }
    out.push(rule_line("╰", "╯", width));
    out
}

pub fn bar_lines(state: &InputState, width: usize, height: u16, reserved: u16) -> Vec<String> {
    if width < 24 {
        return Vec::new();
    }
    let available = height.saturating_sub(reserved) as usize;
    let mut bar = bar_rows(state, width);
    if bar.len() + 4 > available {
        return Vec::new();
    }
    let mut tabs = if height >= 16 { tab_rows(width) } else { Vec::new() };
    if !tabs.is_empty() && tabs.len() + bar.len() + 4 > available {
        tabs.clear();
    }
    if !tabs.is_empty() {
        tabs.pop();
        let first: Vec<char> = bar[0].chars().collect();
        let middle: String = first[1..first.len() - 1].iter().collect();
        bar[0] = format!("├{}┤", middle);
    }
    tabs.extend(bar);
    tabs
}

pub fn draw_bar(frame: &mut Frame, lines: &[String], full: Rect, inner_height: u16) {
    if lines.is_empty() {
        return;
    }
    let rect = Rect {
        x: full.x,
        y: full.y + inner_height,
        width: full.width,
        height: lines.len() as u16,
    };
    frame.render_widget(
        Paragraph::new(lines.join("\n")).style(Style::default().fg(Color::White)),
        rect,
    );
}

fn box_lines(title: &str, lines: &[String], width: usize) -> Vec<String> {
    let inner = width.saturating_sub(4);
    let head = format!("╭─ {} ", title);
    let fill = width.saturating_sub(head.chars().count() + 1);
    let mut out = vec![cut(&format!("{}{}╮", head, "─".repeat(fill)), width)];
    for line in lines {
        out.push(format!("│ {} │", pad(line, inner)));
    }
    out.push(format!("╰{}╯", "─".repeat(width.saturating_sub(2))));
    out
}

fn table_lines(title: &str, headers: (&str, &str), rows: &[(&str, &str)]) -> Vec<String> {
    let mut first = headers.0.chars().count();
    let mut second = headers.1.chars().count();
    for row in rows {
        first = first.max(row.0.chars().count());
        second = second.max(row.1.chars().count());
    }
    let head = format!("╭─ {} ", title);
    let total = first + second + 7;
    let need = head.chars().count() + 1;
    if need > total {
        second += need - total;
    }
    let total = first + second + 7;
    let mut out = vec![format!(
        "{}{}╮",
        head,
        "─".repeat(total.saturating_sub(head.chars().count() + 1))
    )];
    out.push(format!("│ {} │ {} │", pad(headers.0, first), pad(headers.1, second)));
    out.push(format!("├{}┼{}┤", "─".repeat(first + 2), "─".repeat(second + 2)));
    for row in rows {
        out.push(format!("│ {} │ {} │", pad(row.0, first), pad(row.1, second)));
    }
    out.push(format!("╰{}┴{}╯", "─".repeat(first + 2), "─".repeat(second + 2)));
    out
}

fn menu_cells(cells: &[String], inner: usize) -> Vec<String> {
    let widest = cells.iter().map(|cell| cell.chars().count()).max().unwrap_or(1);
    let cell_width = widest + 2;
    let per_row = ((inner + 2) / cell_width).max(1);
    cells
        .chunks(per_row)
        .map(|chunk| {
            let row: String = chunk.iter().map(|cell| pad(cell, cell_width)).collect();
            row.trim_end().to_string()
        })
        .collect()
}

fn menu_lines(width: usize) -> Vec<String> {
    let groups: Vec<(&str, Vec<&str>)> = vec![
        ("move", vec!["t h > between boxes", "d n > command or output"]),
        ("view", vec!["e > expand folded box"]),
        ("mark", vec!["s > mark box"]),
        (
            "copy",
            vec!["c > box", "p > pair", "a > marked", "y > last output", "Y > last pair"],
        ),
        ("leave", vec!["i > insert", "/ > search", "q > quit"]),
    ];
    let mut inside: Vec<String> = Vec::new();
    for (name, cells) in groups {
        let owned: Vec<String> = cells.iter().map(|cell| cell.to_string()).collect();
        let rows = menu_cells(&owned, width.saturating_sub(8));
        inside.extend(box_lines(name, &rows, width.saturating_sub(4)));
    }
    let mut out = table_lines("modes · switch to", ("mode", "key"), &[("insert", "i"), ("search", "/")]);
    out.extend(box_lines("visual general [any] · keys", &inside, width));
    out.into_iter().map(|line| cut(&line, width)).collect()
}

pub fn draw_menu(frame: &mut Frame, state: &InputState, area: Rect) {
    if state.mode != Mode::Visual || !menu_open() {
        return;
    }
    let lines = menu_lines(area.width as usize);
    let count = lines.len().min(area.height as usize);
    let rect = Rect {
        x: area.x,
        y: area.y + ((area.height as usize - count) / 2) as u16,
        width: area.width,
        height: count as u16,
    };
    let text = lines.into_iter().take(count).collect::<Vec<String>>().join("\n");
    frame.render_widget(Clear, rect);
    frame.render_widget(Paragraph::new(text).style(Style::default().fg(Color::White)), rect);
}
