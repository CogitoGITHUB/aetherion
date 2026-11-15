use crate::input_state::{InputState, Mode};
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::widgets::{Clear, Paragraph};
use std::sync::atomic::{AtomicBool, Ordering};

static MENU_OPEN: AtomicBool = AtomicBool::new(false);

pub fn toggle_menu() {
    MENU_OPEN.fetch_xor(true, Ordering::Relaxed);
}

pub fn close_menu() {
    MENU_OPEN.store(false, Ordering::Relaxed);
}

fn menu_open() -> bool {
    MENU_OPEN.load(Ordering::Relaxed)
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

fn bar_rows(_state: &InputState, width: usize) -> Vec<String> {
    let title = directory_name();
    vec![
        edge_line("╭", "╮", &title, width),
        rule_line("╰", "╯", width),
    ]
}

pub fn flow_rows(state: &InputState, width: usize) -> Vec<String> {
    if width < 24 {
        return Vec::new();
    }
    let by = state
        .infos
        .last()
        .and_then(|info| info.as_ref())
        .map(|info| info.by.clone())
        .unwrap_or_else(|| String::from("user"));
    let title = format!("{}: {}", by, directory_name());
    let mut rows = bar_rows(state, width);
    rows[0] = edge_line("╭", "╮", &title, width);
    let first: Vec<char> = rows[0].chars().collect();
    let middle: String = first[1..first.len() - 1].iter().collect();
    rows[0] = format!("├{}┤", middle);
    rows
}

pub fn start_rows(width: usize) -> Vec<String> {
    let mut rows = tab_rows(width);
    rows.pop();
    rows
}

fn tab_base(width: usize) -> Vec<String> {
    let inner = width.saturating_sub(4).max(1);
    let chars: Vec<char> = directory_path().chars().collect();
    let mut rows: Vec<String> = chars.chunks(inner).map(|part| part.iter().collect()).collect();
    if rows.len() > 5 {
        let extra = rows.len() - 5;
        rows.drain(0..extra);
        let rest: String = rows[0].chars().skip(1).collect();
        rows[0] = format!("\u{2026}{}", rest);
    }
    let mut out = context_rows(width);
    if out.is_empty() {
        out.push(edge_line("╭", "╮", "directory", width));
    } else {
        out.pop();
        out.push(edge_line("├", "┤", "directory", width));
    }
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
    let mut top = crate::status_bar::status_lines(width, available.saturating_sub(tabs.len()));
    top.extend(tabs);
    let tabs = top;
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
        Paragraph::new(lines.iter().map(|l| match l.split_once("\u{1}") { Some((a, b)) => ratatui::text::Line::from(vec![ratatui::text::Span::styled(a.to_string(), Style::default().fg(Color::White)), ratatui::text::Span::styled(b.to_string(), Style::default().fg(Color::Red).add_modifier(ratatui::style::Modifier::BOLD))]), None => ratatui::text::Line::from(l.clone()) }).collect::<Vec<ratatui::text::Line>>()).style(Style::default().fg(Color::White)),
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
        ("edit", vec!["x > clear input box"]), ("jump", vec!["z > zoxide picker", "Z > add this dir to zoxide"]), ("dev", vec!["m > dev mode on or off, off builds changed", "M > build everything changed"]),
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

static FULL_INPUT: AtomicBool = AtomicBool::new(false);

pub fn toggle_full_input() {
    FULL_INPUT.fetch_xor(true, Ordering::Relaxed);
}

pub fn close_full_input() {
    FULL_INPUT.store(false, Ordering::Relaxed);
}

pub fn open_full_input() {
    FULL_INPUT.store(true, Ordering::Relaxed);
}

pub fn draw_full_input(frame: &mut Frame, state: &InputState, area: Rect) {
    if !FULL_INPUT.load(Ordering::Relaxed) || state.mode == Mode::Search {
        return;
    }
    let width = area.width as usize;
    if width < 8 || area.height < 4 {
        return;
    }
    let inner = width - 3;
    let mut rows: Vec<String> = Vec::new();
    for part in state.text.split(char::from(10u8)) {
        let chars: Vec<char> = part.chars().collect();
        if chars.is_empty() {
            rows.push(String::new());
        }
        for piece in chars.chunks(inner) {
            rows.push(piece.iter().collect());
        }
    }
    if state.mode == Mode::Insert {
        let full = rows.last().map(|row| row.chars().count() >= inner).unwrap_or(true);
        if full {
            rows.push(String::from("█"));
        } else if let Some(last) = rows.last_mut() {
            last.push_str("█");
        }
    }
    let keep = area.height as usize - 2;
    if rows.len() > keep {
        let extra = rows.len() - keep;
        rows.drain(0..extra);
    }
    let frame_box = crate::box_frame::BoxFrame {
        title: String::from("full input  esc visual  f closes"),
        rows,
    };
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(frame_box.lines(width).join("\n")).style(Style::default().fg(Color::White)),
        area,
    );
}
fn context_box(width: usize) -> Vec<String> {
    let parts = crate::context_bar::parts();
    if parts.is_empty() {
        return Vec::new();
    }
    let inner = width.saturating_sub(4).max(1);
    let mut lines: Vec<String> = Vec::new();
    let mut cur = String::new();
    for p in parts {
        let need = cur.chars().count() + 2 + p.chars().count();
        if !cur.is_empty() && need > inner {
            lines.push(std::mem::take(&mut cur));
        }
        if !cur.is_empty() {
            cur.push_str("  ");
        }
        cur.push_str(&p);
    }
    if !cur.is_empty() {
        lines.push(cur);
    }
    let mut out = vec![edge_line("╭", "╮", "aiu context", width)];
    for l in lines {
        out.push(body_line(&l, width));
    }
    out.push(rule_line("╰", "╯", width));
    out
}

fn context_rows(width: usize) -> Vec<String> {
    let git = crate::splash_bar::git_text(width.saturating_sub(4));
    let mut ctx = context_box(width);
    if git.is_empty() {
        return ctx;
    }
    let mut out = vec![edge_line("╭", "╮", "aiu git", width)];
    for l in git {
        out.push(body_line(&l, width));
    }
    if ctx.is_empty() {
        out.push(rule_line("╰", "╯", width));
        return out;
    }
    ctx.remove(0);
    out.push(edge_line("├", "┤", "aiu context", width));
    out.extend(ctx);
    out
}

pub fn home_rows(width: usize) -> Vec<String> {
    let lines = crate::splash_bar::home_text(width.saturating_sub(4));
    if lines.is_empty() {
        return Vec::new();
    }
    let mut out = vec![edge_line("╭", "╮", "aiu home", width)];
    for l in lines {
        out.push(body_line(&l, width));
    }
    out.push(rule_line("╰", "╯", width));
    out
}

fn tab_rows(width: usize) -> Vec<String> {
    let mut out = tab_base(width);
    let home = home_rows(width);
    if home.is_empty() {
        return out;
    }
    out.pop();
    out.push(edge_line("├", "┤", "aiu home", width));
    out.extend(home.into_iter().skip(1));
    out
}

pub fn draw_splash(frame: &mut Frame, state: &InputState, area: Rect) {
    if !crate::splash_bar::overlay_open() {
        crate::splash_bar::set_offset(0);
        return;
    }
    if state.mode != Mode::Visual {
        crate::splash_bar::close_all();
        return;
    }
    let width = area.width as usize;
    if width < 24 || area.height < 4 {
        return;
    }
    let shown = crate::splash_bar::overlay(width.saturating_sub(4));
    let (name, mut lines) = match shown {
        Some(x) => x,
        None => return,
    };
    if lines.is_empty() {
        lines.push(String::from("nothing to show here"));
    }
    let keep = area.height as usize - 2;
    let max = lines.len().saturating_sub(keep);
    let off = crate::splash_bar::offset().min(max);
    crate::splash_bar::set_offset(off);
    let rows: Vec<String> = lines.into_iter().skip(off).take(keep).collect();
    let frame_box = crate::box_frame::BoxFrame {
        title: format!("{}  up down scroll  j k close", name),
        rows,
    };
    let text = frame_box.lines(width).join("\n");
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(text).style(Style::default().fg(Color::White)),
        area,
    );
}

static BOX_SCROLL: std::sync::atomic::AtomicIsize =
    std::sync::atomic::AtomicIsize::new(0);
static BOX_LAST: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(usize::MAX);
static BOX_OPEN: AtomicBool = AtomicBool::new(false);

pub fn scroll_box(delta: isize) {
    BOX_SCROLL.fetch_add(delta, Ordering::Relaxed);
}

pub fn scroll_any(delta: isize) {
    if crate::splash_bar::overlay_open() {
        crate::splash_bar::scroll(delta);
    } else {
        scroll_box(delta);
    }
}

pub fn box_skip(
    state: &InputState,
    start: usize,
    end: usize,
    pad: usize,
    window: usize,
    base: usize,
) -> usize {
    let open = state.expanded.contains(&state.focus);
    let last = BOX_LAST.swap(state.focus, Ordering::Relaxed);
    let was = BOX_OPEN.swap(open, Ordering::Relaxed);
    if last != state.focus || was != open {
        BOX_SCROLL.store(0, Ordering::Relaxed);
    }
    if state.mode != Mode::Visual {
        return base;
    }
    let height = end.saturating_sub(start);
    if height <= window {
        BOX_SCROLL.store(0, Ordering::Relaxed);
        return base;
    }
    let max = (height - window) as isize;
    let cur = BOX_SCROLL.load(Ordering::Relaxed);
    let off = cur.max(0).min(max);
    BOX_SCROLL.store(off, Ordering::Relaxed);
    start + pad + off as usize
}

pub fn close_rule(width: usize) -> String {
    rule_line("╰", "╯", width)
}
