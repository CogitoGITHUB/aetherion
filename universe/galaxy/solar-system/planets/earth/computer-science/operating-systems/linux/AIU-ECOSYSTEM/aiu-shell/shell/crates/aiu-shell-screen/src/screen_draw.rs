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

pub fn draw_screen(frame: &mut Frame, state: &InputState) {
    let full_area = frame.area();
    let bar = crate::bar_view::bar_lines(state, full_area.width as usize, full_area.height, INPUT_HEIGHT + search_box_height(state, full_area.height));
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
    let pairs_height = area.height - INPUT_HEIGHT - search_height;
    crate::bar_view::draw_bar(frame, &bar, full_area, pairs_height);
    let width = area.width as usize;
    let mut lines: Vec<Line> = Vec::new();
    let mut focus_start: usize = 0;
    let mut focus_end: usize = 0;
    for (pair_index, pair) in state.pairs.iter().enumerate() {
        let boxes = [
            (&pair.command, Color::White, pair_index * 2),
            (&pair.output, Color::White, pair_index * 2 + 1),
        ];
        for (current, _base, flat) in boxes {
            let focused = state.mode == Mode::Visual && state.focus == flat;
            let marked = state.marked.contains(&flat);
            let failed = output_failed(&pair.output.rows);
            let color = if failed {
                Color::Red
            } else if state.mode == Mode::Visual && !focused && !marked {
                Color::Rgb(110, 110, 110)
            } else {
                Color::White
            };
            let mut style = Style::default().fg(color);
            if focused {
                style = style.add_modifier(Modifier::BOLD);
            }
            if marked {
                style = style.add_modifier(Modifier::UNDERLINED);
            }
            if focused {
                focus_start = lines.len();
            }
            let running_box = state.job.is_some() && flat + 1 == state.pairs.len() * 2;
            let collapsed = current.rows.len() > 4 && !state.expanded.contains(&flat) && !running_box;
            let shown_box = if collapsed {
                let mut rows: Vec<String> = current.rows.iter().take(4).cloned().collect();
                rows.push(format!("… {} more rows, e expands", current.rows.len() - 4));
                BoxFrame { title: current.title.clone(), rows }
            } else {
                BoxFrame { title: current.title.clone(), rows: current.rows.clone() }
            };
            let mut shown_box = shown_box;
            if running_box {
                shown_box.title = format!("{} {} running", shown_box.title, spinner_frame(state.tick));
            }
            for text in shown_box.lines(width) {
                lines.push(Line::from(Span::styled(text, style)));
            }
            if focused {
                focus_end = lines.len();
            }
        }
    }
    let window = pairs_height as usize;
    let mut skip = lines.len().saturating_sub(window);
    if state.mode == Mode::Visual {
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
            "input  f full screen edit",
            Color::White,
        ),
        Mode::Insert => ("input insert  esc visual  enter run  up down history  ctrl+r search", Color::White),
        Mode::Search => (
            "input search  type to filter  enter use  esc close",
            Color::White,
        ),
    };
    let mut row = state.text.replace("\n", "⏎");
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
        height: INPUT_HEIGHT,
    };
    let text = input_box.lines(width).join("\n");
    frame.render_widget(Paragraph::new(text).style(Style::default().fg(color)), input_rect);
    draw_search(frame, state, area, pairs_height + bar.len() as u16, search_height);
    crate::bar_view::draw_menu(frame, state, area);
    crate::bar_view::draw_full_input(frame, state, full_area);
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
        format!("{} running  ctrl+c or ctrl+d stops", spinner_frame(state.tick))
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

fn search_row(state: &InputState, position: usize, inner: usize) -> Line {
    let (row_index, positions) = &state.search_matches[position];
    let row = &state.search_rows[*row_index];
    let selected = position == state.search_index;
    let border = Style::default().fg(Color::White);
    let base = if selected {
        Style::default().fg(Color::White).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::White)
    };
    let light = Style::default().fg(Color::White).add_modifier(Modifier::BOLD).add_modifier(Modifier::UNDERLINED);
    let (mark, mark_color) = match row.exit {
        Some(0) => ("✓", Color::White),
        Some(_) => ("✗", Color::Red),
        None => (" ", Color::White),
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
        spans.push(Span::styled(tail, Style::default().fg(Color::White)));
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
    let border = Style::default().fg(Color::White);
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
