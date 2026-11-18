use crate::box_frame::BoxFrame;
use crate::history_view::format_age;
use crate::input_state::{InputState, Mode};
use std::time::{SystemTime, UNIX_EPOCH};
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;

const INPUT_HEIGHT: u16 = 3;

fn wrap_box_rows(rows: &[String], limit: usize) -> Vec<String> {
    let size = limit.max(1);
    let mut wrapped: Vec<String> = Vec::new();
    for row in rows {
        let letters: Vec<char> = row.chars().collect();
        if letters.is_empty() {
            wrapped.push(String::new());
            continue;
        }
        for piece in letters.chunks(size) {
            wrapped.push(piece.iter().collect());
        }
    }
    wrapped
}

pub fn draw_screen(frame: &mut Frame, state: &InputState) {
    let input_height: u16 = if state.mode == Mode::Visual && !state.flashing() { 0 } else { INPUT_HEIGHT };
    let full_area = frame.area();
    let in_flow = !state.pairs.is_empty();
    let center = !in_flow && input_height > 0 && state.mode != Mode::Search;
    let bar = if center { crate::status_bar::status_lines(full_area.width as usize, full_area.height as usize / 3) } else if in_flow { Vec::new() } else { crate::bar_view::bar_lines(state, full_area.width as usize, full_area.height, input_height + search_box_height(state, full_area.height)) };
    let area = Rect {
        x: full_area.x,
        y: full_area.y,
        width: full_area.width,
        height: full_area.height - bar.len() as u16,
    };
    if area.width < 4 || area.height <= INPUT_HEIGHT {
        return;
    }
    let search_height = search_box_height(state, area.height);
    let mid_want = in_flow && state.mode != Mode::Search && full_area.width >= 24 && full_area.height >= 24;
    let mid_dir = if mid_want { crate::bar_view::start_rows(full_area.width as usize).len() as u16 } else { 0 };
    let mid_total = mid_dir + if input_height > 0 { input_height } else { 1 };
    let mid_top = (full_area.height / 2).saturating_sub(mid_dir + 1).min(full_area.height.saturating_sub(mid_total));
    let mid_flow = mid_want && mid_top >= 4;
    let pairs_height = if mid_flow { mid_top } else { area.height - input_height - search_height };
    crate::bar_view::draw_bar(frame, &bar, full_area, 0);
    let width = area.width as usize;
    let flow_bar = if in_flow && !mid_flow { crate::bar_view::flow_rows(state, width) } else { Vec::new() };
    let mut lines: Vec<Line> = Vec::new();
    let mut focus_start: usize = 0;
    let mut focus_end: usize = 0;
    for (pair_index, pair) in state.pairs.iter().enumerate() {
        let boxes = [
            (&pair.command, crate::theme::text(), pair_index * 2),
            (&pair.output, crate::theme::text(), pair_index * 2 + 1),
        ];
        for (current, _base, flat) in boxes {
            let focused = state.mode == Mode::Visual && state.focus == flat;
            let marked = state.marked.contains(&flat);
let start_track = if state.mode == Mode::Visual { focused } else { flat / 2 + 1 == state.pairs.len() && flat % 2 == 0 };
let end_track = if state.mode == Mode::Visual { focused } else { flat / 2 + 1 == state.pairs.len() };
            let failed = output_failed(&pair.output.rows);
            let color = if state.pair_running(pair_index) {
crate::theme::dim()
} else if failed {
                crate::theme::error()
            } else if state.mode == Mode::Visual && !focused && !marked {
                crate::theme::dim()
            } else {
                crate::theme::text()
            };
            let mut style = Style::default().fg(color);
            if focused {
                style = style.add_modifier(Modifier::BOLD);
            }
            if marked {
                style = style.add_modifier(Modifier::UNDERLINED);
            }
            if start_track {
                focus_start = lines.len();
            }
            let running_box = state.job.is_some() && flat + 1 == state.pairs.len() * 2;
            let collapsed = current.rows.len() > 4 && !state.expanded.contains(&flat) && !running_box;
            let shown_box = if collapsed {
                let mut rows: Vec<String> = current.rows.iter().take(4).cloned().collect();
                rows.push(format!("… {} more rows, e expands", current.rows.len() - 4));
                BoxFrame { title: current.title.clone(), rows }
            } else {
                if state.expanded.contains(&flat) {
                    BoxFrame { title: current.title.clone(), rows: wrap_box_rows(&current.rows, width.saturating_sub(4)) }
                } else {
                    BoxFrame { title: current.title.clone(), rows: current.rows.clone() }
                }
            };
            let mut shown_box = shown_box;
            if running_box {
                shown_box.title = format!("command running {}", spinner_frame(state.tick));
            }
            for text in shown_box.lines(width) {
                lines.push(Line::from(Span::styled(text, style)));
            }
            if flat % 2 == 1 && state.info_open.contains(&pair_index) {
                let info_box = BoxFrame {
                    title: format!("info {}", pair_index + 1),
                    rows: state.info_rows(pair_index),
                };
                for text in info_box.lines(width) {
                    lines.push(Line::from(Span::styled(text, style)));
                }
            }
            if end_track {
                focus_end = lines.len();
            }
        }
    }
    if !flow_bar.is_empty() {
        let _ = lines.pop();
        for text in flow_bar {
            let white = Style::default().fg(crate::theme::text());
            lines.push(Line::from(Span::styled(text, white)));
        }
        if state.mode != Mode::Visual {
            focus_end = lines.len();
        }
    }
    let (pairs_height, mid_top) = if mid_flow && lines.len() > mid_top as usize {
        let limit = full_area.height.saturating_sub(mid_total) as usize;
        let grown = lines.len().min(limit).max(mid_top as usize) as u16;
        (grown, grown)
    } else {
        (pairs_height, mid_top)
    };
    let window = pairs_height as usize;
    let mut skip = lines.len().saturating_sub(window);
    if !state.pairs.is_empty() {
        let middle = (focus_start + focus_end) / 2;
        let pad = window / 2;
        let mut padded: Vec<Line> = Vec::new();
        for _ in 0..pad {
            padded.push(Line::from(""));
        }
        padded.append(&mut lines);
        for _ in 0..pad {
            padded.push(Line::from(""));
        }
        lines = padded;
        skip = (middle + pad).saturating_sub(window / 2);
        skip = crate::bar_view::box_skip(
            state, focus_start, focus_end, pad, window, skip,
        );
    }
    if mid_flow && (state.mode != Mode::Visual || state.focus + 1 == state.pairs.len() * 2) && !state.pairs.is_empty() {
        let pad = window / 2;
        skip = (lines.len() - pad).saturating_sub(window);
    }
    if state.job.is_some() && !state.pairs.is_empty() && (state.mode != Mode::Visual || state.focus + 1 == state.pairs.len() * 2) {
        let tail = (focus_end + window / 2).saturating_sub(window);
        skip = skip.max(tail);
    }
    let shown: Vec<Line> = lines.into_iter().skip(skip).collect();
    let pairs_rect = Rect {
        x: area.x,
        y: area.y,
        width: area.width,
        height: pairs_height,
    };
    frame.render_widget(Paragraph::new(shown), pairs_rect);

    let (title, color) = match state.mode {
        Mode::Visual => (
            "input  f full screen edit  z jump  Z add dir  w website",
            crate::theme::text(),
        ),
        Mode::Insert => ("input insert  esc visual  enter run  up down history  ctrl+r search", crate::theme::text()),
        Mode::Search => (
            "input search  type to filter  enter use  esc close",
            crate::theme::text(),
        ),
    };
    let mut row = state.text.replace("\n", "⏎");
    if state.flashing() { row = state.notice.clone(); }
    if state.mode == Mode::Insert || state.mode == Mode::Search {
        row.push_str("█");
    }
    let keep_chars = width.saturating_sub(4);
    let row_count = row.chars().count();
    if row_count > keep_chars && keep_chars > 1 {
        let tail: String = row.chars().skip(row_count - keep_chars + 1).collect();
        row = format!("\u{2026}{}", tail);
    }
    let input_box = BoxFrame {
        title: input_title(state, title),
        rows: vec![row],
    };
    let input_rect = Rect {
        x: area.x,
        y: area.y + pairs_height + bar.len() as u16,
        width: area.width,
        height: input_height,
    };
    let mut input_lines = input_box.lines(width);
    let mut input_rect = input_rect;
    if center {
        let mut group = crate::bar_view::start_rows(width);
        if let Some(top) = input_lines.first_mut() {
            let body: String = top.chars().skip(1).collect();
            let keep = body.chars().count().saturating_sub(1);
            let middle: String = body.chars().take(keep).collect();
            *top = format!("├{}┤", middle);
        }
        let dir_len = group.len() as u16;
        let total = dir_len + input_lines.len() as u16;
        group.extend(input_lines);
        let mid = full_area.height / 2;
        let limit = full_area.height.saturating_sub(total);
        let top_y = mid.saturating_sub(dir_len + 1).min(limit);
        input_rect = Rect {
            x: area.x,
            y: full_area.y + top_y,
            width: area.width,
            height: total.min(full_area.height),
        };
        input_lines = group;
    }
    if mid_flow {
        let mut group = crate::bar_view::start_rows(width);
        if input_height > 0 {
            if let Some(top) = input_lines.first_mut() {
                let body: String = top.chars().skip(1).collect();
                let keep = body.chars().count().saturating_sub(1);
                let middle: String = body.chars().take(keep).collect();
                *top = format!("├{}┤", middle);
            }
            group.extend(input_lines);
        } else {
            group.push(crate::bar_view::close_rule(width));
        }
        input_rect = Rect {
            x: area.x,
            y: full_area.y + mid_top,
            width: area.width,
            height: (group.len() as u16).min(full_area.height),
        };
        input_lines = group;
    }
    let text = input_lines.join("\n");
    frame.render_widget(Paragraph::new(text).style(Style::default().fg(color)), input_rect);
    draw_search(frame, state, area, pairs_height + bar.len() as u16, search_height);
    crate::bar_view::draw_menu(frame, state, area);
    crate::bar_view::draw_full_input(frame, state, full_area);
    crate::bar_view::draw_splash(frame, state, full_area);
    if state.job.is_some() {
        let errored = state.pairs.last().map(|p| output_failed(&p.output.rows)).unwrap_or(false);
        let tone = pulse_color_for(state.tick, errored);
        for cell in frame.buffer_mut().content.iter_mut() {
            if cell.symbol().trim().is_empty() {
                continue;
            }
            let fg = cell.fg;
            if fg == crate::theme::error() || fg == crate::theme::text() || fg == Color::Reset || fg == crate::theme::dim() {
                cell.set_fg(tone);
            }
        }
    }
    crate::notify::draw_notify(frame, full_area);
}

fn output_failed(rows: &[String]) -> bool {
    let exit_row = rows.last().map(|row| row.starts_with("exit ")).unwrap_or(false);
    exit_row || rows.iter().any(|row| row.starts_with("Error:"))
}

fn spinner_frame(tick: usize) -> char {
    "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏".chars().nth(tick % 10).unwrap_or(char::from(46u8))
}

fn input_title(state: &InputState, title: &str) -> String {
    if state.job.is_some() {
        String::new()
    } else if (state.mode == Mode::Visual) && !state.notice.is_empty() {
        format!("{}  {}", state.notice, title)
    } else {
        String::from(title)
    }
}

fn now_milliseconds() -> i64 {    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

fn search_box_height(state: &InputState, screen_height: u16) -> u16 {
    if state.mode != Mode::Search {
        return 0;
    }
    let wanted = (state.search_matches.len().min(10) + 2) as u16;
    wanted.max(4).min(screen_height.saturating_sub(INPUT_HEIGHT + 1))
}

fn search_row(state: &InputState, position: usize, inner: usize) -> Line<'_> {
    let (row_index, positions) = &state.search_matches[position];
    let row = &state.search_rows[*row_index];
    let selected = position == state.search_index;
    let border = Style::default().fg(crate::theme::text());
    let base = if selected {
        Style::default().fg(crate::theme::text()).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(crate::theme::text())
    };
    let light = Style::default().fg(crate::theme::text()).add_modifier(Modifier::BOLD).add_modifier(Modifier::UNDERLINED);
    let (mark, mark_color) = match row.exit {
        Some(0) => ("✓", crate::theme::text()),
        Some(_) => ("✗", crate::theme::error()),
        None => (" ", crate::theme::text()),
    };
    let age = match row.when_ms {
        Some(then) => format_age(now_milliseconds(), then),
        None => String::from("now"),
    };
    let directory: String = row.dir.chars().take(14).collect();
    let tail = format!("  {:>8}  {:<14}", age, directory);
    let show_meta = inner >= 50;
    let meta_width = if show_meta { 1 + tail.chars().count() } else { 0 };
    let command_width = inner.saturating_sub(meta_width + 5);
    let marker = if selected { "▶ " } else { "  " };
    let command_text = row.command.replace("\n", " ").replace("\t", " ");
    let mut spans: Vec<Span> = vec![Span::styled("│ ", border), Span::styled(marker, base)];
    let mut used = 0;
    for (index, c) in command_text.chars().take(command_width).enumerate() {
        let style = if positions.contains(&index) { light } else { base };
        spans.push(Span::styled(c.to_string(), style));
        used += 1;
    }
    spans.push(Span::styled(" ".repeat(command_width - used + 1), base));
    if show_meta {
        spans.push(Span::styled(mark, Style::default().fg(mark_color)));
        spans.push(Span::styled(tail, Style::default().fg(crate::theme::text())));
    }
    spans.push(Span::styled(" │", border));
    Line::from(spans)
}

fn draw_search(
    frame: &mut Frame,
    state: &InputState,
    area: Rect,
    pairs_height: u16,
    search_height: u16,
) {
    if state.mode != Mode::Search || search_height < 3 {
        return;
    }
    let width = area.width as usize;
    let inner = width - 2;
    let visible = (search_height - 2) as usize;
    let total = state.search_matches.len();
    let first = if state.search_index >= visible {
        state.search_index + 1 - visible
    } else {
        0
    };
    let end = (first + visible).min(total);
    let shown = if total == 0 { 0 } else { state.search_index + 1 };
    let title = format!(
        "history  {} of {}  up older  down newer  enter use  esc close",
        shown, total
    );
    let edges = BoxFrame {
        title,
        rows: Vec::new(),
    }
    .lines(width);
    let border = Style::default().fg(crate::theme::text());
    let mut lines: Vec<Line> = Vec::new();
    lines.push(Line::from(Span::styled(edges[0].clone(), border)));
    for _ in 0..(visible - (end - first)) {
        lines.push(Line::from(Span::styled(
            format!("│{}│", " ".repeat(inner)),
            border,
        )));
    }
    for position in (first..end).rev() {
        lines.push(search_row(state, position, inner));
    }
    lines.push(Line::from(Span::styled(edges[1].clone(), border)));
    let rect = Rect {
        x: area.x,
        y: area.y + pairs_height,
        width: area.width,
        height: search_height,
    };
    frame.render_widget(Paragraph::new(lines), rect);
}

fn pulse_level(tick: usize) -> u8 {
    let phase = tick % 30;
    let up = if phase < 15 { phase } else { 30 - phase };
    (110 + up * 145 / 15) as u8
}

fn pulse_color(tick: usize) -> Color {
    let stops = [crate::theme::rgb("dim"),
        crate::theme::rgb("text"),
        crate::theme::rgb("error")];
    let phase = tick % 60;
    let seg = phase / 20;
    let t = (phase % 20) as f32 / 20.0;
    let from = stops[seg];
    let to = stops[(seg + 1) % 3];
    let mix = |a: f32, b: f32| (a + (b - a) * t) as u8;
    Color::Rgb(mix(from.0, to.0), mix(from.1, to.1), mix(from.2, to.2))
}

fn pulse_color_for(tick: usize, red: bool) -> Color {
    if red {
        return pulse_color(tick);
    }
    let phase = tick % 40;
    let up = if phase < 20 { phase } else { 40 - phase };
    let t = up as f32 / 20.0;
    let a = crate::theme::rgb("dim");
    let b = crate::theme::rgb("text");
    let m = |x: f32, y: f32| (x + (y - x) * t) as u8;
    Color::Rgb(m(a.0, b.0), m(a.1, b.1), m(a.2, b.2))
}
