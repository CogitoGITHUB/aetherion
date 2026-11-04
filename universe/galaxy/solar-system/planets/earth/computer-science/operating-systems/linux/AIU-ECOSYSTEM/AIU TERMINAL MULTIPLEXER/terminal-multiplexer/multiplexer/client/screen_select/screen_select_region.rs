use super::*;

impl Screen {
    /// select_command runs one command of the selection: the point moves
    /// over the visible text of the focused pane, the mark is the
    /// anchor, and the region is the text between the mark and the
    /// point.
    pub(super) fn select_command(&mut self, command: Command) -> Action {
        let lines = self.select_lines();
        match command {
            Command::SelectLeft => self.select.left(&lines),
            Command::SelectRight => self.select.right(&lines),
            Command::SelectUp => self.select.up(&lines),
            Command::SelectDown => self.select.down(&lines),
            Command::SelectWordLeft => self.select.word_left(&lines),
            Command::SelectWordRight => self.select.word_right(&lines),
            Command::SelectMark => {
                self.select.set_mark();
                self.message = "the mark is set where the point stands".to_string();
            }
            Command::SelectPopMark => {
                self.select.pop_mark();
                self.message = "the mark is popped; the anchor below it stands".to_string();
            }
            Command::SelectCopy => return self.copy_region(&lines),
            Command::SelectCopyLine => return self.copy_line(&lines),
            Command::SelectCopyOut => return self.copy_out(&lines),
            Command::SelectSend => return self.send_region(&lines),
            Command::SelectAgentHere => return self.agent_here(&lines),
            Command::PasteClipboard => return self.paste_clipboard(),
            Command::PageUp | Command::PageDown => {
                // The view scrolled, so the text under the point is fresh
                // text: the pick starts again over it, and the mark that
                // named a line of the old window is gone with it.
                let up = command == Command::PageUp;
                if self.scroll_view(up) {
                    self.select.restart();
                    self.message = format!(
                        "the view scrolled; the pick starts again over the fresh text ({} back)",
                        self.scroll_distance()
                    );
                } else {
                    self.message =
                        "the view did not move, so the pick stands where it stands".to_string();
                }
            }
            Command::LeaveSelect => {
                self.mode = Mode::Visual;
                self.message =
                    "the selection is closed: nothing was copied and nothing was sent".to_string();
            }
            _ => {}
        }
        Action::Nothing
    }

    /// select_lines answers the visible lines of the focused pane: the
    /// lines the multiplexer draws, so a line that has scrolled out of
    /// the pane cannot be picked, because it cannot be seen.
    pub(super) fn select_lines(&self) -> Vec<String> {
        let cols = self.cols.max(20);
        let (top, area_rows) = self.area();
        let rects = self.rects(cols, area_rows, top);
        let members = self.tab_panes();
        let at = match members.iter().position(|index| *index == self.focused) {
            Some(at) => at,
            None => return Vec::new(),
        };
        let rect = match rects.get(at) {
            Some(rect) => rect,
            None => return Vec::new(),
        };
        let height = rect.rows.saturating_sub(2) as usize;
        self.window(members[at], height)
    }

    /// copy_region puts the region into the multiplexer's own ring, and
    /// answers the line it copied.
    pub(super) fn copy_region(&mut self, lines: &[String]) -> Action {
        let text = self.select.region(lines);
        if text.is_empty() {
            self.message = "there is no region: the mark is not set".to_string();
            return Action::Nothing;
        }
        self.ring.insert(0, text.clone());
        if self.ring.len() > RING_KEPT {
            self.ring.pop();
        }
        self.message = format!("the region is copied: {}", first_line(&text));
        Action::Nothing
    }

    /// copy_line puts the line the point stands on into the
    /// multiplexer's own ring.
    pub(super) fn copy_line(&mut self, lines: &[String]) -> Action {
        let text = self.select.line_text(lines);
        if text.is_empty() {
            self.message = "the line is empty".to_string();
            return Action::Nothing;
        }
        self.ring.insert(0, text.clone());
        if self.ring.len() > RING_KEPT {
            self.ring.pop();
        }
        self.message = format!("the line is copied: {}", first_line(&text));
        Action::Nothing
    }

    /// copy_out puts the region on the Android clipboard, and into the
    /// multiplexer's own ring with it: one pick, two places, and the ring
    /// stays the owner's own even when the phone's clipboard is not there.
    ///
    /// The bytes go to the owner's terminal, not to a pane: the sequence is
    /// the terminal's own, and the pane's program would print it.
    pub(super) fn copy_out(&mut self, lines: &[String]) -> Action {
        let text = self.select.region(lines);
        if text.is_empty() {
            self.message = "there is no region: the mark is not set".to_string();
            return Action::Nothing;
        }
        let out = match clipboard::out(&text) {
            Ok(bytes) => bytes,
            Err(why) => {
                // The refusal names what would not fit, and the ring keeps
                // the text all the same: the owner's own copy is not lost to
                // the phone's limit.
                self.ring.insert(0, text.clone());
                if self.ring.len() > RING_KEPT {
                    self.ring.pop();
                }
                self.message = why;
                return Action::Nothing;
            }
        };
        self.ring.insert(0, text.clone());
        if self.ring.len() > RING_KEPT {
            self.ring.pop();
        }
        // The write is the one route that works, and it works while the
        // Termux terminal is in the foreground: the line says what it did
        // and what the route needs, and never claims more than that.
        self.message = format!(
            "the region went out to the Android clipboard: {} \
             (it lands while the termux terminal is in the foreground)",
            first_line(&text)
        );
        Action::Terminal(out)
    }

    /// copy_lines copies the lines of a pane into the multiplexer's own ring,
    /// the ring the owner's own copy fills. The lines are the pane's own
    /// lines, counted from one, and the view shows that count, so the owner
    /// and the agent name the same line.
    pub(super) fn copy_lines(&mut self, name: &str, first: &str, last: &str) -> bool {
        let first_at: usize = match first.parse() {
            Ok(value) => value,
            Err(_) => {
                self.message = format!("{} is not a line number", first);
                return false;
            }
        };
        let last_at: usize = match last.parse() {
            Ok(value) => value,
            Err(_) => {
                self.message = format!("{} is not a line number", last);
                return false;
            }
        };
        let copied = {
            let mut error = String::new();
            let text = match self.panes.iter().find(|pane| pane.name == name) {
                Some(pane) => {
                    if pane.lines.is_empty() {
                        error = format!("the pane {} has said nothing yet", name);
                        String::new()
                    } else if first_at > pane.lines.len() {
                        error = format!("the pane {} holds {} lines", name, pane.lines.len());
                        String::new()
                    } else {
                        let from = first_at.max(1);
                        let to = last_at.max(from).min(pane.lines.len());
                        pane.lines[from - 1..to].join("\n")
                    }
                }
                None => {
                    error = format!("there is no pane named {}", name);
                    String::new()
                }
            };
            (text, error)
        };
        if !copied.1.is_empty() {
            self.message = copied.1;
            return false;
        }
        let text = copied.0;
        if text.is_empty() {
            self.message = "there is nothing to copy".to_string();
            return false;
        }
        self.ring.insert(0, text.clone());
        if self.ring.len() > RING_KEPT {
            self.ring.pop();
        }
        self.message = format!(
            "the lines {} to {} of {} are copied: {}",
            first_at,
            last_at.max(first_at),
            name,
            first_line(&text)
        );
        true
    }
}
