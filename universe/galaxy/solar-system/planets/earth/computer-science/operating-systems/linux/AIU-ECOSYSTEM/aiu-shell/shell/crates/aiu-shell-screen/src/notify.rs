use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::widgets::{Clear, Paragraph};
use std::sync::Mutex;
use std::time::{Duration, Instant};

struct Note {
    level: String,
    text: String,
    until: Instant,
}

static NOTES: Mutex<Vec<Note>> = Mutex::new(Vec::new());

pub fn notify(level: &str, text: &str) {
    let secs = match level {
        "error" => 5,
        "warn" => 3,
        _ => 2,
    };
    if let Ok(mut g) = NOTES.lock() {
        g.retain(|n| n.text != text);
        g.push(Note {
            level: level.to_string(),
            text: text.to_string(),
            until: Instant::now() + Duration::from_secs(secs),
        });
        while g.len() > 3 {
            g.remove(0);
        }
    }
}

pub fn take_notice(notice: &mut String, age: &mut u32) {
    if notice.is_empty() {
        return;
    }
    if notice.as_str() == crate::input_state::RUNNING_NOTICE {
        return;
    }
    notify("info", notice.as_str());
    notice.clear();
    *age = 0;
}

fn wrap(text: &str, n: usize) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut line = String::new();
    for word in text.split_whitespace() {
        let word: String = word.chars().take(n).collect();
        let used = line.chars().count();
        let add = word.chars().count();
        let need = if used == 0 { add } else { used + 1 + add };
        if need > n && used > 0 {
            out.push(std::mem::take(&mut line));
        }
        if !line.is_empty() {
            line.push_str(" ");
        }
        line.push_str(&word);
    }
    if !line.is_empty() {
        out.push(line);
    }
    out
}

fn pad(text: &str, width: usize) -> String {
    let mut out: String = text.chars().take(width).collect();
    let used = out.chars().count();
    out.push_str(&" ".repeat(width - used));
    out
}

fn box_of(level: &str, text: &str, w: usize) -> Vec<String> {
    let head = format!("╭─┤ {} ├", level);
    let fill = w.saturating_sub(head.chars().count() + 1);
    let mut out = vec![format!("{}{}╮", head, "─".repeat(fill))];
    for l in wrap(text, w - 4) {
        out.push(format!("│ {} │", pad(&l, w - 4)));
    }
    out.push(format!("╰{}╯", "─".repeat(w - 2)));
    out
}

pub fn draw_notify(frame: &mut Frame, area: Rect) {
    let now = Instant::now();
    let items: Vec<(String, String)> = match NOTES.lock() {
        Ok(mut g) => {
            g.retain(|n| n.until > now);
            g.iter()
                .map(|n| (n.level.clone(), n.text.clone()))
                .collect()
        }
        Err(_) => return,
    };
    let w = (area.width as usize).saturating_sub(2).min(40);
    if items.is_empty() || w < 12 {
        return;
    }
    let mut row: u16 = 1;
    for (level, text) in items {
        let lines = box_of(&level, &text, w);
        let h = lines.len() as u16;
        if row + h + 1 > area.height {
            break;
        }
        let rect = Rect {
            x: area.x + area.width - w as u16 - 1,
            y: area.y + row,
            width: w as u16,
            height: h,
        };
        let color = if level == "error" {
            crate::theme::error()
        } else {
            crate::theme::text()
        };
        frame.render_widget(Clear, rect);
        frame.render_widget(
            Paragraph::new(lines.join("\n"))
                .style(Style::default().fg(color)),
            rect,
        );
        row += h;
    }
}
