use super::*;

impl Screen {
    pub fn key(&mut self, bytes: &[u8]) -> Vec<Action> {
        let mut actions: Vec<Action> = Vec::new();
        let mut at = 0;
        while at < bytes.len() {
            if self.reserved {
                self.reserved = false;
                let now = self.reserved_key(bytes[at]);
                if !matches!(now, Action::Nothing) {
                    actions.push(now);
                }
                at += 1;
                continue;
            }
            match self.mode {
                Mode::Insert => {
                    if bytes[at] == RESERVED_PREFIX {
                        self.reserved = true;
                        at += 1;
                        continue;
                    }
                    let mut end = at;
                    while end < bytes.len() {
                        if bytes[end] == ESCAPE {
                            if end + 1 < bytes.len() && bytes[end + 1] == b'[' {
                                end += 3;
                                continue;
                            }
                            break;
                        }
                        if bytes[end] == RESERVED_PREFIX {
                            break;
                        }
                        end += 1;
                    }
                    if end > at {
                        actions.push(Action::Send(bytes[at..end].to_vec()));
                        at = end;
                        continue;
                    }
                    self.mode = Mode::Visual;
                    self.message = "visual".to_string();
                    at += 1;
                }
                Mode::Command => {
                    let now = self.command_key(bytes[at]);
                    if !matches!(now, Action::Nothing) {
                        actions.push(now);
                    }
                    at += 1;
                }
                Mode::Select => {
                    let arrow = bytes[at] == ESCAPE
                        && at + 2 < bytes.len()
                        && bytes[at + 1] == b'[';
                    if bytes[at] == ESCAPE && !arrow {
                        self.mode = Mode::Visual;
                        self.message =
                            "the selection is closed: nothing was copied and nothing was sent"
                                .to_string();
                        at += 1;
                        continue;
                    }
                    let end = if arrow { at + 3 } else { at + 1 };
                    for byte in bytes[at..end].iter() {
                        let now = self.select_key(*byte);
                        if !matches!(now, Action::Nothing) {
                            actions.push(now);
                        }
                    }
                    at = end;
                }
                Mode::Visual | Mode::Explorer => {
                    let now = self.visual_key(bytes[at]);
                    if !matches!(now, Action::Nothing) {
                        actions.push(now);
                    }
                    at += 1;
                }
            }
        }
        actions
    }

    pub(super) fn visual_key(&mut self, key: u8) -> Action {
        let mode = self.mode;
        match self.keymap.resolve(mode, key) {
            Resolution::Command(command) => {
                if mode == Mode::Explorer {
                    self.close_panel();
                }
                self.run(command)
            }
            Resolution::Map(context) => {
                if mode == Mode::Explorer {
                    self.keymap.open_map(context);
                    self.show_explorer();
                    return Action::Nothing;
                }
                Action::Nothing
            }
            Resolution::Pending => Action::Nothing,
            Resolution::Pass => Action::Nothing,
            Resolution::Ignore => {
                if mode == Mode::Visual && key < 0x20 && key != ESCAPE {
                    return Action::Send(vec![key]);
                }
                if mode == Mode::Explorer && key == ESCAPE {
                    self.close_panel();
                    self.mode = Mode::Visual;
                }
                Action::Nothing
            }
        }
    }

    pub(super) fn reserved_key(&mut self, key: u8) -> Action {
        match self.keymap.resolve(Mode::Visual, key) {
            Resolution::Command(command) => self.run(command),
            Resolution::Map(context) => {
                self.keymap.open_map(context);
                self.show_explorer();
                Action::Nothing
            }
            Resolution::Pending => Action::Nothing,
            Resolution::Pass => Action::Nothing,
            Resolution::Ignore => Action::Nothing,
        }
    }

    pub(super) fn select_key(&mut self, key: u8) -> Action {
        match self.keymap.resolve(Mode::Select, key) {
            Resolution::Command(command) => self.select_command(command),
            Resolution::Map(_) => Action::Nothing,
            Resolution::Pending => Action::Nothing,
            Resolution::Pass => Action::Nothing,
            Resolution::Ignore => Action::Nothing,
        }
    }

    pub(super) fn command_key(&mut self, byte: u8) -> Action {
        match byte {
            ESCAPE => {
                self.mode = Mode::Visual;
                self.command.clear();
                Action::Nothing
            }
            ENTER | b'\n' => {
                let said = self.command.trim().to_string();
                self.command.clear();
                self.mode = Mode::Visual;
                self.run_command(&said)
            }
            BACKSPACE => {
                self.command.pop();
                Action::Nothing
            }
            byte if byte >= 0x20 => {
                if self.command.chars().count() < 200 {
                    self.command.push(byte as char);
                }
                Action::Nothing
            }
            _ => Action::Nothing,
        }
    }
}
