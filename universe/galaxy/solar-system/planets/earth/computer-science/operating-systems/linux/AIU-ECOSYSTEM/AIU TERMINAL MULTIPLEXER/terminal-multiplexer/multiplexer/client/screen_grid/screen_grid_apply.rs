use std::collections::HashMap;
use std::sync::Mutex;

const BLANK: char = 32u8 as char;
const HISTORY_KEPT: usize = 2000;
const CODE_ESCAPE: u32 = 27;
const CODE_BELL: u32 = 7;
const CODE_BACKSPACE: u32 = 8;
const CODE_TAB: u32 = 9;
const CODE_LINE_FEED: u32 = 10;
const CODE_RETURN: u32 = 13;

enum SequenceState {
    Plain,
    Escaped,
    Csi,
    Osc,
    SkipOne,
}

struct PaneGrid {
    cols: usize,
    rows: usize,
    cells: Vec<Vec<char>>,
    history: Vec<String>,
    row: usize,
    col: usize,
    state: SequenceState,
    sequence: String,
}

fn row_text(cells: &[char]) -> String {
    cells.iter().collect::<String>().trim_end().to_string()
}

impl PaneGrid {
    fn new(cols: usize, rows: usize) -> PaneGrid {
        PaneGrid {
            cols,
            rows,
            cells: vec![vec![BLANK; cols]; rows],
            history: Vec::new(),
            row: 0,
            col: 0,
            state: SequenceState::Plain,
            sequence: String::new(),
        }
    }

    fn fit(&mut self, cols: usize, rows: usize) {
        if cols == self.cols && rows == self.rows {
            return;
        }
        for line in self.cells.iter_mut() {
            line.resize(cols, BLANK);
        }
        self.cells.resize(rows, vec![BLANK; cols]);
        self.cols = cols;
        self.rows = rows;
        self.row = self.row.min(rows - 1);
        self.col = self.col.min(cols - 1);
    }

    fn blank_line(&self) -> Vec<char> {
        vec![BLANK; self.cols]
    }

    fn line_feed(&mut self) {
        if self.row + 1 < self.rows {
            self.row += 1;
        } else {
            let gone = self.cells.remove(0);
            self.history.push(row_text(&gone));
            if self.history.len() > HISTORY_KEPT {
                let extra = self.history.len() - HISTORY_KEPT;
                self.history.drain(0..extra);
            }
            let blank = self.blank_line();
            self.cells.push(blank);
        }
    }

    fn put(&mut self, character: char) {
        if self.col >= self.cols {
            self.col = 0;
            self.line_feed();
        }
        self.cells[self.row][self.col] = character;
        self.col += 1;
    }

    fn fill(&mut self, row: usize, from: usize, to: usize) {
        let to = to.min(self.cols);
        if row < self.rows {
            for column in from..to {
                self.cells[row][column] = BLANK;
            }
        }
    }

    fn erase_line(&mut self, mode: usize) {
        match mode {
            0 => self.fill(self.row, self.col, self.cols),
            1 => self.fill(self.row, 0, self.col + 1),
            _ => self.fill(self.row, 0, self.cols),
        }
    }

    fn erase_display(&mut self, mode: usize) {
        match mode {
            0 => {
                self.erase_line(0);
                for row in (self.row + 1)..self.rows {
                    self.fill(row, 0, self.cols);
                }
            }
            1 => {
                for row in 0..self.row {
                    self.fill(row, 0, self.cols);
                }
                self.erase_line(1);
            }
            _ => {
                for row in 0..self.rows {
                    self.fill(row, 0, self.cols);
                }
            }
        }
    }

    fn apply_csi(&mut self, params: &str, final_character: char) {
        let private = params
            .chars()
            .next()
            .map(|first| "?>=<".contains(first))
            .unwrap_or(false);
        if private {
            return;
        }
        let numbers: Vec<usize> = params.split(";").map(|part| part.parse().unwrap_or(0)).collect();
        let first = numbers.first().copied().unwrap_or(0);
        let step = first.max(1);
        let second = numbers.get(1).copied().unwrap_or(0);
        let last_row = self.rows - 1;
        let last_col = self.cols - 1;
        match final_character.to_string().as_str() {
            "A" => self.row = self.row.saturating_sub(step),
            "B" => self.row = (self.row + step).min(last_row),
            "C" => self.col = (self.col + step).min(last_col),
            "D" => self.col = self.col.saturating_sub(step),
            "G" => self.col = (step - 1).min(last_col),
            "d" => self.row = (step - 1).min(last_row),
            "H" | "f" => {
                self.row = (step - 1).min(last_row);
                self.col = (second.max(1) - 1).min(last_col);
            }
            "J" => self.erase_display(first),
            "K" => self.erase_line(first),
            "L" => {
                for _ in 0..step {
                    let blank = self.blank_line();
                    self.cells.insert(self.row, blank);
                    self.cells.truncate(self.rows);
                }
            }
            "M" => {
                for _ in 0..step {
                    self.cells.remove(self.row);
                    let blank = self.blank_line();
                    self.cells.push(blank);
                }
            }
            "P" => {
                let (row, col, cols) = (self.row, self.col, self.cols);
                let line = &mut self.cells[row];
                for _ in 0..step {
                    if col < cols {
                        line.remove(col);
                        line.push(BLANK);
                    }
                }
            }
            "@" => {
                let (row, col, cols) = (self.row, self.col, self.cols);
                let line = &mut self.cells[row];
                for _ in 0..step {
                    line.insert(col, BLANK);
                    line.truncate(cols);
                }
            }
            "X" => {
                let end = (self.col + step).min(self.cols);
                self.fill(self.row, self.col, end);
            }
            _ => {}
        }
    }

    fn feed_character(&mut self, character: char) {
        let code = character as u32;
        match self.state {
            SequenceState::Plain => match code {
                CODE_ESCAPE => self.state = SequenceState::Escaped,
                CODE_RETURN => self.col = 0,
                CODE_LINE_FEED => self.line_feed(),
                CODE_BACKSPACE => self.col = self.col.saturating_sub(1),
                CODE_TAB => self.col = ((self.col / 8 + 1) * 8).min(self.cols - 1),
                CODE_BELL => {}
                _ if code < 32 => {}
                _ => self.put(character),
            },
            SequenceState::Escaped => {
                self.state = match character.to_string().as_str() {
                    "[" => {
                        self.sequence.clear();
                        SequenceState::Csi
                    }
                    "]" => SequenceState::Osc,
                    "(" | ")" => SequenceState::SkipOne,
                    _ => SequenceState::Plain,
                };
            }
            SequenceState::Csi => {
                if (64..=126).contains(&code) {
                    let params = std::mem::take(&mut self.sequence);
                    self.state = SequenceState::Plain;
                    self.apply_csi(&params, character);
                } else {
                    self.sequence.push(character);
                }
            }
            SequenceState::Osc => {
                if code == CODE_BELL {
                    self.state = SequenceState::Plain;
                } else if code == CODE_ESCAPE {
                    self.state = SequenceState::SkipOne;
                }
            }
            SequenceState::SkipOne => self.state = SequenceState::Plain,
        }
    }
}

static PANE_GRIDS: Mutex<Option<HashMap<String, PaneGrid>>> = Mutex::new(None);

pub(crate) fn grid_lines_after(pane: &str, raw: &str, cols: usize, rows: usize) -> Vec<String> {
    let cols = cols.max(1);
    let rows = rows.max(1);
    let mut held = PANE_GRIDS.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let grids = held.get_or_insert_with(HashMap::new);
    let grid = grids
        .entry(pane.to_string())
        .or_insert_with(|| PaneGrid::new(cols, rows));
    grid.fit(cols, rows);
    for character in raw.chars() {
        grid.feed_character(character);
    }
    let mut lines = grid.history.clone();
    for row in grid.cells.iter() {
        lines.push(row_text(row));
    }
    lines
}
