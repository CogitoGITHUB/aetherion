use super::*;

impl Screen {
    /// key reads the keys the owner pressed and answers what the client must
    /// do about them.
    ///
    /// A chunk of keys is read one at a time, so a key that changes the mode
    /// leaves the rest of the chunk to the new mode. Every key that means
    /// something is answered, in order: a paste of text is a paste of text,
    /// not the last byte of it.
    pub fn key(&mut self, bytes: &[u8]) -> Vec<Action> {
        let mut actions: Vec<Action> = Vec::new();
        let mut at = 0;
        while at < bytes.len() {
            // The reserved prefix is the multiplexer's own in every mode:
            // the next key is read in the root map, whatever stands.
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
                    // The keys belong to the program in the pane: the whole
                    // run of them goes as it was typed. A lone Escape leaves
                    // Insert, and it is not sent on.
                    let mut end = at;
                    while end < bytes.len() {
                        if bytes[end] == ESCAPE {
                            if end + 1 < bytes.len() && bytes[end + 1] == b'[' {
                                // an arrow key: it belongs to the program
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
                    // One key at a time: the enter key ends the command
                    // line, and the keys after it belong to the screen
                    // again.
                    let now = self.command_key(bytes[at]);
                    if !matches!(now, Action::Nothing) {
                        actions.push(now);
                    }
                    at += 1;
                }
                Mode::Select => {
                    // The escape stands alone or it begins an arrow key:
                    // the byte stream knows that, and the map does not.
                    let arrow = bytes[at] == ESCAPE
                        && at + 2 < bytes.len()
                        && bytes[at + 1] == b'[';
                    if bytes[at] == ESCAPE && !arrow {
                        // The escape leaves the selection and does nothing
                        // else: no text is copied, no bundle is sent and
                        // no pane opens.
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

    /// visual_key reads one key in VISUAL or in the EXPLORER, and answers what
    /// the client must do.
    pub(super) fn visual_key(&mut self, key: u8) -> Action {
        let mode = self.mode;
        match self.keymap.resolve(mode, key) {
            Resolution::Command(command) => {
                if mode == Mode::Explorer {
                    // A command run from the explorer leaves it, and the
                    // owner is back where the command belongs.
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
                // In VISUAL a group opens and waits for the next key.
                Action::Nothing
            }
            Resolution::Pending => Action::Nothing,
            Resolution::Pass => Action::Nothing,
            Resolution::Ignore => {
                if mode == Mode::Visual && key < 0x20 && key != ESCAPE {
                    // A Control key belongs to the program in the pane: the
                    // owner must still be able to interrupt it.
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

    /// reserved_key reads one key that came after the reserved prefix: it is
    /// the multiplexer's own, read in the root map whatever mode stands, so
    /// the owner reaches the multiplexer from inside a program that has the
    /// keyboard.
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

    /// select_key reads one key in the SELECTION and answers what the
    /// client must do.
    ///
    /// The selection is an overlay on the visual mode: the mode line
    /// says which mode stands, and the escape leaves the selection and
    /// does nothing else.
    pub(super) fn select_key(&mut self, key: u8) -> Action {
        match self.keymap.resolve(Mode::Select, key) {
            Resolution::Command(command) => self.select_command(command),
            Resolution::Map(_) => Action::Nothing,
            Resolution::Pending => Action::Nothing,
            Resolution::Pass => Action::Nothing,
            Resolution::Ignore => Action::Nothing,
        }
    }

    /// command_key reads a key in the COMMAND line: the words are the
    /// multiplexer's.
    pub(super) fn command_key(&mut self, byte: u8) -> Action {
        match byte {
            ESCAPE => {
                self.mode = Mode::Visual;
                self.command.clear();
                Action::Nothing
            }
            // The enter key, however it arrives: a terminal sends a
            // carriage return, a pipe sends a line feed.
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
