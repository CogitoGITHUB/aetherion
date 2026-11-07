pub struct BoxFrame {
    pub title: String,
    pub rows: Vec<String>,
}

fn fit_to_width(text: &str, width: usize) -> String {
    let mut out: String = text.chars().take(width).collect();
    let used = out.chars().count();
    out.push_str(&" ".repeat(width - used));
    out
}

impl BoxFrame {
    pub fn height(&self) -> usize {
        self.rows.len() + 2
    }

    pub fn lines(&self, width: usize) -> Vec<String> {
        if width < 4 {
            return Vec::new();
        }
        let inner = width - 2;
        let label: String = format!(" {} ", self.title).chars().take(inner - 1).collect();
        let fill = inner - 1 - label.chars().count();
        let mut out = Vec::new();
        out.push(format!("╭─{}{}╮", label, "─".repeat(fill)));
        for row in &self.rows {
            out.push(format!("│{}│", fit_to_width(&format!(" {}", row), inner)));
        }
        out.push(format!("╰{}╯", "─".repeat(inner)));
        out
    }
}

#[cfg(test)]
mod tests {
    use super::BoxFrame;

    #[test]
    fn every_row_has_the_full_width() {
        let frame_box = BoxFrame {
            title: String::from("a long title that does not fit"),
            rows: vec![
                String::from("one"),
                String::from("a row that is much too long for the box"),
            ],
        };
        for width in 4..40 {
            let lines = frame_box.lines(width);
            assert_eq!(lines.len(), frame_box.height());
            for line in lines {
                assert_eq!(line.chars().count(), width);
            }
        }
    }

    #[test]
    fn too_narrow_draws_nothing() {
        let frame_box = BoxFrame {
            title: String::from("x"),
            rows: vec![String::from("y")],
        };
        assert!(frame_box.lines(3).is_empty());
    }
}
