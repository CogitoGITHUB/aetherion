use crate::box_frame::BoxFrame;
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::widgets::Paragraph;

pub struct CommandPair {
    pub command: BoxFrame,
    pub output: BoxFrame,
}

fn frame_box_from_text(title: &str, rows: &[&str]) -> BoxFrame {
    BoxFrame {
        title: String::from(title),
        rows: rows.iter().map(|row| String::from(*row)).collect(),
    }
}

pub fn sample_pairs() -> Vec<CommandPair> {
    vec![
        CommandPair {
            command: frame_box_from_text("command 1", &["ls aiu-shell"]),
            output: frame_box_from_text(
                "output 1",
                &["README.md", "reedline", "shell", "starship", "todo.aiu"],
            ),
        },
        CommandPair {
            command: frame_box_from_text("command 2", &["cargo build -j 4"]),
            output: frame_box_from_text(
                "output 2",
                &[
                    "Compiling aiu-shell-protocol",
                    "Compiling aiu-shell-engine",
                    "Compiling aiu-shell-parser",
                    "Compiling aiu-shell-command",
                    "Compiling aiu-shell-cmd-base",
                    "Compiling aiu-shell-cli",
                    "Compiling aiu-shell-screen",
                    "Finished dev profile",
                ],
            ),
        },
        CommandPair {
            command: frame_box_from_text("command 3", &["echo hello"]),
            output: frame_box_from_text("output 3", &["hello"]),
        },
    ]
}

pub fn draw_pairs(frame: &mut Frame, pairs: &[CommandPair]) {
    let area = frame.area();
    let mut used_height: u16 = 0;
    for pair in pairs {
        let boxes = [(&pair.command, Color::Cyan), (&pair.output, Color::Green)];
        for (current, color) in boxes {
            let remaining = area.height.saturating_sub(used_height);
            if remaining == 0 {
                return;
            }
            let shown = (current.height() as u16).min(remaining);
            let text = current
                .lines(area.width as usize)
                .into_iter()
                .take(shown as usize)
                .collect::<Vec<String>>()
                .join("\n");
            let rect = Rect {
                x: area.x,
                y: area.y + used_height,
                width: area.width,
                height: shown,
            };
            frame.render_widget(Paragraph::new(text).style(Style::default().fg(color)), rect);
            used_height += shown;
        }
    }
}

pub struct PairInfo {
    pub started: std::time::Instant,
    pub duration: Option<std::time::Duration>,
    pub exit: Option<Option<i32>>,
    pub cwd: String,
    pub by: String,
}
