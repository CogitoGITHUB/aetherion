
#[derive(Clone, Debug, Default)]
pub struct Selection {
    pub point: (usize, usize),
    pub marks: Vec<(usize, usize)>,
}

impl Selection {
    pub fn new() -> Selection {
        Selection {
            point: (0, 0),
            marks: Vec::new(),
        }
    }

    pub fn left(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        if column > 0 {
            self.point = (line, column - 1);
            return;
        }
        if line > 0 {
            let above = lines.get(line - 1).map(|text| text.chars().count()).unwrap_or(0);
            self.point = (line - 1, above);
        }
    }

    pub fn right(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        let width = lines.get(line).map(|text| text.chars().count()).unwrap_or(0);
        if column < width {
            self.point = (line, column + 1);
            return;
        }
        if line + 1 < lines.len() {
            self.point = (line + 1, 0);
        }
    }

    pub fn up(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        if line > 0 {
            let above = lines.get(line - 1).map(|text| text.chars().count()).unwrap_or(0);
            self.point = (line - 1, column.min(above));
        }
    }

    pub fn down(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        if line + 1 < lines.len() {
            let below = lines.get(line + 1).map(|text| text.chars().count()).unwrap_or(0);
            self.point = (line + 1, column.min(below));
        }
    }

    pub fn word_left(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        let text = lines.get(line).cloned().unwrap_or_default();
        let characters: Vec<char> = text.chars().collect();
        let mut at = column.min(characters.len());
        while at > 0 && characters[at - 1].is_whitespace() {
            at -= 1;
        }
        while at > 0 && !characters[at - 1].is_whitespace() {
            at -= 1;
        }
        self.point = (line, at);
    }

    pub fn word_right(&mut self, lines: &[String]) {
        let (line, column) = self.point;
        let text = lines.get(line).cloned().unwrap_or_default();
        let characters: Vec<char> = text.chars().collect();
        let mut at = column.min(characters.len());
        while at < characters.len() && !characters[at].is_whitespace() {
            at += 1;
        }
        while at < characters.len() && characters[at].is_whitespace() {
            at += 1;
        }
        self.point = (line, at);
    }

    pub fn set_mark(&mut self) {
        self.marks.push(self.point);
    }

    pub fn pop_mark(&mut self) {
        self.marks.pop();
    }

    pub fn restart(&mut self) {
        self.point = (0, 0);
        self.marks.clear();
    }

    pub fn mark(&self) -> Option<(usize, usize)> {
        self.marks.last().copied()
    }

    pub fn region(&self, lines: &[String]) -> String {
        let mark = match self.mark() {
            Some(mark) => mark,
            None => return String::new(),
        };
        let (from, to) = if mark <= self.point {
            (mark, self.point)
        } else {
            (self.point, mark)
        };
        let mut text = String::new();
        for line in from.0..=to.0 {
            if line >= lines.len() {
                break;
            }
            let characters: Vec<char> = lines[line].chars().collect();
            let start = if line == from.0 { from.1.min(characters.len()) } else { 0 };
            let end = if line == to.0 { to.1.min(characters.len()) } else { characters.len() };
            if start < end {
                text.push_str(&characters[start..end].iter().collect::<String>());
            }
            if line != to.0 {
                text.push('\n');
            }
        }
        text
    }

    pub fn line_text(&self, lines: &[String]) -> String {
        lines.get(self.point.0).cloned().unwrap_or_default()
    }

    pub fn marked(&self, lines: &[String]) -> Vec<String> {
        let mark = match self.mark() {
            Some(mark) => mark,
            None => return lines.to_vec(),
        };
        let (from, to) = if mark <= self.point {
            (mark, self.point)
        } else {
            (self.point, mark)
        };
        let mut marked: Vec<String> = Vec::new();
        for (at, text) in lines.iter().enumerate() {
            if at < from.0 || at > to.0 {
                marked.push(text.clone());
                continue;
            }
            let characters: Vec<char> = text.chars().collect();
            let start = if at == from.0 { from.1.min(characters.len()) } else { 0 };
            let end = if at == to.0 { to.1.min(characters.len()) } else { characters.len() };
            if end <= start {
                marked.push(text.clone());
                continue;
            }
            let mut line = String::new();
            line.push_str(&characters[..start].iter().collect::<String>());
            line.push_str("\x1b[7m");
            line.push_str(&characters[start..end].iter().collect::<String>());
            line.push_str("\x1b[0m");
            line.push_str(&characters[end..].iter().collect::<String>());
            marked.push(line);
        }
        marked
    }
}

#[cfg(test)]
#[path = "select_test/select_test_behavior.rs"]
mod tests;
