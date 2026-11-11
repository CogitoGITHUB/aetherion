use crate::box_frame::BoxFrame;
use crate::command_runner::{RunningJob, start_line};
use crate::history_view::{HistoryRow, filter_rows, load_database_rows, unique_commands};
use crate::pair_screen::{CommandPair, sample_pairs};
use crossterm::event::{KeyCode, KeyEvent, KeyEventKind, KeyModifiers};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Visual,
    Insert,
    Search,
}

pub struct InputState {
    pub mode: Mode,
    pub text: String,
    pub history: Vec<String>,
    pub cursor: Option<usize>,
    pub pairs: Vec<CommandPair>,
    pub quit: bool,
    pub run_commands: bool,
    pub focus: usize,
    pub marked: Vec<usize>,
    pub search_rows: Vec<HistoryRow>,
    pub search_matches: Vec<(usize, Vec<usize>)>,
    pub search_index: usize,
    pub search_from: Mode,
    pub search_saved: String,
    pub pending_copy: Option<String>,
    pub notice: String,
    pub job: Option<RunningJob>,
    pub tick: usize,
    pub block_until_job_done: bool,
    pub expanded: Vec<usize>,
}

impl Default for InputState {
    fn default() -> Self {
        Self::new()
    }
}

impl InputState {
    pub fn new() -> Self {
        let history = ["ls aiu-shell", "cargo build -j 4", "echo hello"]
            .iter()
            .map(|line| String::from(*line))
            .collect();
        Self {
            mode: Mode::Visual,
            text: String::new(),
            history,
            cursor: None,
            pairs: sample_pairs(),
            quit: false,
            run_commands: false,
            focus: 5,
            marked: Vec::new(),
            search_rows: Vec::new(),
            search_matches: Vec::new(),
            search_index: 0,
            search_from: Mode::Visual,
            search_saved: String::new(),
            pending_copy: None,
            notice: String::new(),
            job: None,
            tick: 0,
            block_until_job_done: false,
            expanded: Vec::new(),
        }
    }

    pub fn new_running() -> Self {
        let mut state = Self::new();
        state.pairs.clear();
        state.focus = 0;
        state.history.clear();
        state.run_commands = true;
        state
    }

    fn rows_of_box(&self, flat: usize) -> Option<Vec<String>> {
        let pair = self.pairs.get(flat / 2)?;
        if flat % 2 == 0 {
            Some(pair.command.rows.clone())
        } else {
            Some(pair.output.rows.clone())
        }
    }

    fn copy_boxes(&mut self, key: &str) {
        let text = match key {
            "c" => self.rows_of_box(self.focus).map(|rows| rows.join("\n")),
            "p" => {
                let first = self.focus - self.focus % 2;
                let mut rows = self.rows_of_box(first).unwrap_or_default();
                rows.extend(self.rows_of_box(first + 1).unwrap_or_default());
                Some(rows.join("\n"))
            }
            _ => {
                let mut order = self.marked.clone();
                order.sort();
                let parts: Vec<String> = order
                    .iter()
                    .filter_map(|flat| self.rows_of_box(*flat))
                    .map(|rows| rows.join("\n"))
                    .collect();
                if parts.is_empty() {
                    None
                } else {
                    Some(parts.join("\n\n"))
                }
            }
        };
        match text {
            Some(text) => {
                self.notice = format!("copied {} chars", text.chars().count());
                self.pending_copy = Some(text);
            }
            None => self.notice = String::from("nothing to copy"),
        }
    }

    fn copy_last(&mut self, with_command: bool) {
        let Some(last) = self.pairs.len().checked_sub(1) else {
            self.notice = String::from("nothing to copy");
            return;
        };
        let mut rows: Vec<String> = Vec::new();
        if with_command {
            rows.extend(self.rows_of_box(last * 2).unwrap_or_default());
        }
        rows.extend(self.rows_of_box(last * 2 + 1).unwrap_or_default());
        let text = rows.join("\n");
        self.notice = format!("copied {} chars", text.chars().count());
        self.pending_copy = Some(text);
    }

    fn toggle_expand(&mut self) {
        if let Some(position) = self.expanded.iter().position(|mark| *mark == self.focus) {
            self.expanded.remove(position);
        } else {
            self.expanded.push(self.focus);
        }
    }

    fn toggle_mark(&mut self) {
        if let Some(position) = self.marked.iter().position(|mark| *mark == self.focus) {
            self.marked.remove(position);
        } else {
            self.marked.push(self.focus);
        }
    }

    fn move_in_boxes(&mut self, key: &str) {
        let total = self.pairs.len() * 2;
        match key {
            "t" => {
                if self.focus >= 2 {
                    self.focus -= 2;
                }
            }
            "h" => {
                if self.focus + 2 < total {
                    self.focus += 2;
                }
            }
            "d" => {
                if self.focus % 2 == 1 {
                    self.focus -= 1;
                }
            }
            "n" => {
                if self.focus % 2 == 0 && self.focus + 1 < total {
                    self.focus += 1;
                }
            }
            "s" => self.toggle_mark(),
            "e" => self.toggle_expand(),
            "c" | "p" | "a" => self.copy_boxes(key),
            _ => {}
        }
    }

    fn load_search_rows(&self) -> Vec<HistoryRow> {
        let mut rows: Vec<HistoryRow> = self
            .history
            .iter()
            .rev()
            .map(|line| HistoryRow {
                command: line.clone(),
                exit: None,
                when_ms: None,
                dir: String::new(),
            })
            .collect();
        if self.run_commands {
            rows.extend(load_database_rows(3000));
        }
        unique_commands(rows)
    }

    fn refilter(&mut self) {
        self.search_matches = filter_rows(&self.search_rows, &self.text);
        self.search_index = 0;
    }

    fn open_search(&mut self) {
        self.search_from = self.mode;
        self.search_saved = std::mem::take(&mut self.text);
        self.search_rows = self.load_search_rows();
        self.mode = Mode::Search;
        self.refilter();
    }

    fn close_search(&mut self) {
        self.text = std::mem::take(&mut self.search_saved);
        self.mode = self.search_from;
    }

    fn use_search_choice(&mut self) {
        let chosen = self
            .search_matches
            .get(self.search_index)
            .map(|(row, _)| self.search_rows[*row].command.clone());
        match chosen {
            Some(command) => {
                self.text = command;
                self.search_saved.clear();
                self.mode = Mode::Insert;
            }
            None => self.close_search(),
        }
    }

    fn show_older(&mut self) {
        if self.history.is_empty() {
            return;
        }
        let next = match self.cursor {
            None => self.history.len() - 1,
            Some(0) => 0,
            Some(index) => index - 1,
        };
        self.cursor = Some(next);
        self.text = self.history[next].clone();
    }

    fn show_newer(&mut self) {
        let Some(index) = self.cursor else {
            return;
        };
        if index + 1 < self.history.len() {
            self.cursor = Some(index + 1);
            self.text = self.history[index + 1].clone();
        } else {
            self.cursor = None;
            self.text.clear();
        }
    }

    fn start_job(&mut self, line: &str) -> Vec<String> {
        if let Some(message) = crate::command_runner::try_cd(line) { return vec![message]; } match start_line(line) {
            Ok(job) => {
                self.job = Some(job);
                Vec::new()
            }
            Err(message) => vec![message],
        }
    }

    pub fn poll_job(&mut self) {
        let Some(job) = self.job.as_mut() else {
            return;
        };
        let new_rows = job.poll();
        let finished = job.exit;
        let Some(pair) = self.pairs.last_mut() else {
            return;
        };
        let limit = 200;
        for row in new_rows {
            let count = pair.output.rows.len();
            if count == limit {
                pair.output.rows.push(String::from("... output cut"));
            } else if count < limit {
                pair.output.rows.push(row);
            }
        }
        if let Some(code) = finished {
            match code {
                Some(0) => {}
                Some(number) => pair.output.rows.push(format!("exit {}", number)),
                None => pair.output.rows.push(String::from("stopped")),
            }
            if pair.output.rows.is_empty() {
                pair.output.rows.push(String::new());
            }
            self.job = None;
        }
    }

    fn stop_job(&mut self) {
        if let Some(job) = self.job.as_mut() {
            job.stop();
        }
    }

    pub fn wait_for_job(&mut self) {
        for _ in 0..500 {
            if self.job.is_none() {
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
            self.poll_job();
        }
    }

    pub fn paste(&mut self, text: &str) {
        let cleaned = text.replace("\r\n", "\n").replace("\r", "\n");
        if self.mode == Mode::Search {
            self.text.push_str(&cleaned.replace("\n", " "));
            self.refilter();
            return;
        }
        self.mode = Mode::Insert;
        self.text.push_str(cleaned.trim_end_matches("\n"));
        self.cursor = None;
        if self.text.chars().count() > 400 || self.text.lines().count() > 6 {
            crate::bar_view::open_full_input();
        }
    }

    fn keep_line(&mut self) {
        if self.job.is_some() {
            return;
        }
        if self.text.is_empty() {
            return;
        }
        let number = self.pairs.len() + 1;
        let line = std::mem::take(&mut self.text);
        let output_rows = if self.run_commands && crate::command_runner::is_fullscreen_line(&line) {
            crate::command_runner::request_fullscreen(&line);
            vec![String::from("running full screen")]
        } else if self.run_commands {
            self.start_job(&line)
        } else {
            vec![String::from("not run yet")]
        };
        self.pairs.push(CommandPair {
            command: BoxFrame {
                title: format!("command {}", number),
                rows: line.lines().map(String::from).collect(),
            },
            output: BoxFrame {
                title: format!("output {}", number),
                rows: output_rows,
            },
        });
        self.history.push(line);
        self.focus = self.pairs.len() * 2 - 1;
        if self.block_until_job_done {
            self.wait_for_job();
        }
        self.cursor = None;
    }

    pub fn press(&mut self, key: KeyEvent) {
        if key.kind != KeyEventKind::Press {
            return;
        }
        self.notice.clear();
        if key.modifiers.contains(KeyModifiers::CONTROL) {
            if let KeyCode::Char(c) = key.code {
                if (c.to_string() == "c" || c.to_string() == "d") && self.job.is_some() {
                    self.stop_job();
                    return;
                }
                if c.to_string() == "c" || c.to_string() == "d" {
                    self.quit = true;
                }
                if c.to_string() == "r" && self.mode != Mode::Search {
                    self.open_search();
                }
            }
            return;
        }
        match self.mode {
            Mode::Visual => {
                if let KeyCode::Char(c) = key.code {
                    match c.to_string().as_str() {
                        "t" | "h" | "d" | "n" | "e" | "s" | "c" | "p" | "a" => self.move_in_boxes(c.to_string().as_str()),
                        "i" => {
                            crate::bar_view::close_menu();
                            self.mode = Mode::Insert;
                        }
                        "x" => {
                            self.text.clear();
                            self.cursor = None;
                            self.notice = String::from("input cleared");
                        }
                        "y" => self.copy_last(false),
                        "Y" => self.copy_last(true),
                        "/" => self.open_search(),
                        " " => crate::bar_view::toggle_menu(),
                        "f" => crate::bar_view::toggle_full_input(),
                        "m" => { self.notice = crate::command_runner::dev_mode_toggle(); } "M" => { self.notice = crate::command_runner::dev_build_all(); } "z" => crate::command_runner::request_jump(), "Z" => { self.notice = crate::command_runner::add_current_dir(); } "q" => self.quit = true,
                        _ => {}
                    }
                }
            }
            Mode::Search => match key.code {
                KeyCode::Char(c) if c == char::from(32u8) && self.text.ends_with(char::from(32u8)) => {
                    self.text.pop();
                    self.close_search();
                }
                KeyCode::Esc => self.close_search(),
                KeyCode::Enter => self.use_search_choice(),
                KeyCode::Up => {
                    if self.search_index + 1 < self.search_matches.len() {
                        self.search_index += 1;
                    }
                }
                KeyCode::Down => {
                    if self.search_index > 0 {
                        self.search_index -= 1;
                    }
                }
                KeyCode::Backspace => {
                    self.text.pop();
                    self.refilter();
                }
                KeyCode::Char(c) => {
                    self.text.push(c);
                    self.refilter();
                }
                _ => {}
            },
            Mode::Insert => match key.code {
                KeyCode::Char(c) if c == char::from(32u8) && self.text.ends_with(char::from(32u8)) => {
                    self.text.pop();
                    self.mode = Mode::Visual;
                }
                KeyCode::Esc => self.mode = Mode::Visual,
                KeyCode::Enter => {
                    crate::bar_view::close_full_input();
                    self.keep_line();
                    self.mode = Mode::Visual;
                }
                KeyCode::Up => self.show_older(),
                KeyCode::Down => self.show_newer(),
                KeyCode::Backspace => {
                    self.text.pop();
                    self.cursor = None;
                }
                KeyCode::Char(c) => {
                    self.text.push(c);
                    self.cursor = None;
                }
                _ => {}
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{InputState, Mode};
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn type_text(state: &mut InputState, text: &str) {
        for c in text.chars() {
            state.press(KeyEvent::new(KeyCode::Char(c), KeyModifiers::NONE));
        }
    }

    fn press_code(state: &mut InputState, code: KeyCode) {
        state.press(KeyEvent::new(code, KeyModifiers::NONE));
    }

    #[test]
    fn starts_in_visual_mode() {
        let state = InputState::new();
        assert_eq!(state.mode, Mode::Visual);
        assert!(state.text.is_empty());
    }

    #[test]
    fn visual_mode_does_not_type() {
        let mut state = InputState::new();
        type_text(&mut state, "xyz");
        assert!(state.text.is_empty());
    }

    #[test]
    fn insert_types_and_escape_returns() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        assert_eq!(state.mode, Mode::Insert);
        type_text(&mut state, "ab");
        press_code(&mut state, KeyCode::Backspace);
        assert_eq!(state.text, "a");
        press_code(&mut state, KeyCode::Esc);
        assert_eq!(state.mode, Mode::Visual);
    }

    #[test]
    fn enter_keeps_the_line_as_a_new_pair() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        type_text(&mut state, "ls");
        press_code(&mut state, KeyCode::Enter);
        assert_eq!(state.pairs.len(), 4);
        assert_eq!(state.history.len(), 4);
        assert!(state.text.is_empty());
        assert_eq!(state.pairs[3].command.rows[0], "ls");
    }

    #[test]
    fn enter_on_an_empty_line_keeps_nothing() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        press_code(&mut state, KeyCode::Enter);
        assert_eq!(state.pairs.len(), 3);
    }

    #[test]
    fn control_c_quits() {
        let mut state = InputState::new();
        let key = KeyEvent::new(KeyCode::Char(char::from(99u8)), KeyModifiers::CONTROL);
        state.press(key);
        assert!(state.quit);
    }

    #[test]
    fn slash_opens_history_and_typing_filters() {
        let mut state = InputState::new();
        type_text(&mut state, "/");
        assert_eq!(state.mode, Mode::Search);
        assert_eq!(state.search_matches.len(), 3);
        type_text(&mut state, "car");
        assert_eq!(state.search_matches.len(), 1);
        press_code(&mut state, KeyCode::Enter);
        assert_eq!(state.mode, Mode::Insert);
        assert_eq!(state.text, "cargo build -j 4");
    }

    #[test]
    fn escape_closes_history_and_restores_the_typed_text() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        type_text(&mut state, "ab");
        state.press(KeyEvent::new(KeyCode::Char(char::from(114u8)), KeyModifiers::CONTROL));
        assert_eq!(state.mode, Mode::Search);
        type_text(&mut state, "zz");
        press_code(&mut state, KeyCode::Esc);
        assert_eq!(state.mode, Mode::Insert);
        assert_eq!(state.text, "ab");
    }

    #[test]
    fn up_goes_to_older_matches_and_down_back() {
        let mut state = InputState::new();
        type_text(&mut state, "/");
        press_code(&mut state, KeyCode::Up);
        assert_eq!(state.search_index, 1);
        press_code(&mut state, KeyCode::Down);
        press_code(&mut state, KeyCode::Down);
        assert_eq!(state.search_index, 0);
    }

    #[test]
    fn y_copies_the_last_output_and_capital_y_adds_the_command() {
        let mut state = InputState::new();
        type_text(&mut state, "y");
        assert_eq!(state.pending_copy, Some(state.pairs[2].output.rows.join("\n")));
        type_text(&mut state, "Y");
        let both = format!(
            "{}\n{}",
            state.pairs[2].command.rows.join("\n"),
            state.pairs[2].output.rows.join("\n")
        );
        assert_eq!(state.pending_copy, Some(both));
    }

    #[test]
    fn pasted_lines_stay_one_command() {
        let mut state = InputState::new();
        state.paste("echo a\necho b\n");
        assert_eq!(state.mode, Mode::Insert);
        press_code(&mut state, KeyCode::Enter);
        assert_eq!(state.pairs.len(), 4);
        assert_eq!(state.pairs[3].command.rows, vec!["echo a", "echo b"]);
    }

    #[test]
    fn control_d_quits_when_nothing_runs() {
        let mut state = InputState::new();
        state.press(KeyEvent::new(KeyCode::Char(char::from(100u8)), KeyModifiers::CONTROL));
        assert!(state.quit);
    }

    #[test]
    fn t_and_h_move_the_focused_box_in_visual_mode() {
        let mut state = InputState::new();
        assert_eq!(state.focus, 5);
        type_text(&mut state, "t");
        assert_eq!(state.focus, 3);
        type_text(&mut state, "tt");
        assert_eq!(state.focus, 1);
        type_text(&mut state, "h");
        assert_eq!(state.focus, 3);
        type_text(&mut state, "d");
        assert_eq!(state.focus, 2);
        type_text(&mut state, "n");
        assert_eq!(state.focus, 3);
        assert!(state.text.is_empty());
    }

    #[test]
    fn s_marks_e_expands_and_a_copies_in_visual_mode() {
        let mut state = InputState::new();
        type_text(&mut state, "s");
        assert_eq!(state.marked, vec![5]);
        type_text(&mut state, "a");
        assert_eq!(state.pending_copy, Some(state.pairs[2].output.rows.join("\n")));
        type_text(&mut state, "s");
        assert!(state.marked.is_empty());
        type_text(&mut state, "e");
        assert_eq!(state.expanded, vec![5]);
        type_text(&mut state, "e");
        assert!(state.expanded.is_empty());
    }

    #[test]
    fn focus_follows_the_newest_box_after_a_run() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        type_text(&mut state, "ls");
        press_code(&mut state, KeyCode::Enter);
        assert_eq!(state.focus, 7);
    }

    #[test]
    fn up_in_insert_mode_walks_the_history() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        press_code(&mut state, KeyCode::Up);
        assert_eq!(state.text, "echo hello");
        press_code(&mut state, KeyCode::Down);
        assert!(state.text.is_empty());
    }

    #[test]
    fn q_quits_in_visual_mode_only() {
        let mut state = InputState::new();
        type_text(&mut state, "i");
        type_text(&mut state, "q");
        assert!(!state.quit);
        press_code(&mut state, KeyCode::Esc);
        type_text(&mut state, "q");
        assert!(state.quit);
    }
}
