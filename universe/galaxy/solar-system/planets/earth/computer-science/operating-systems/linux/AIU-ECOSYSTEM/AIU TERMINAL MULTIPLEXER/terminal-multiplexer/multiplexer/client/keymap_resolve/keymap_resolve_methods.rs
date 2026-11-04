use super::*;

impl Keymap {
    /// empty is a keymap with nothing typed and the root map open.
    pub fn empty() -> Keymap {
        Keymap {
            pending: Vec::new(),
            group: None,
            explorer: Context::Root,
        }
    }

    /// pending_keys answers the keys of the sequence being typed, in the words
    /// the explorer shows them.
    pub fn pending_keys(&self) -> String {
        if self.pending.is_empty() {
            return String::new();
        }
        let mut text = String::new();
        for byte in &self.pending {
            if !text.is_empty() {
                text.push(' ');
            }
            text.push_str(&key_name(*byte));
        }
        text
    }

    /// group answers the map a sequence opened, if any.
    #[cfg(test)]
    pub fn group(&self) -> Option<Context> {
        self.group
    }

    /// explorer_map answers the map the explorer is showing.
    pub fn explorer_map(&self) -> Context {
        self.explorer
    }

    /// open_map puts the explorer on another map.
    pub fn open_map(&mut self, context: Context) {
        self.explorer = context;
        self.pending.clear();
    }

    /// cancel drops the sequence being typed and the group it opened.
    pub fn cancel(&mut self) {
        self.pending.clear();
        self.group = None;
    }

    /// resolve reads one key and says what it means, in the given mode.
    ///
    /// In INSERT the keys belong to the program in the pane, and only the
    /// Escape is the multiplexer's: it leaves Insert without being sent on.
    /// In VISUAL the keys are the multiplexer's, read against the root map
    /// (or the group a sequence opened). In the EXPLORER the keys are read
    /// against the map the explorer is showing.
    pub fn resolve(&mut self, mode: Mode, key: u8) -> Resolution {
        match mode {
            Mode::Insert => Resolution::Pass,
            Mode::Command => Resolution::Pass,
            Mode::Visual => self.resolve_visual(key),
            Mode::Explorer => self.resolve_explorer(key),
            Mode::Select => self.resolve_select(key),
        }
    }

    /// resolve_select reads one key in the SELECTION against the select
    /// map. The escape leaves the selection, and it is the one key that
    /// is read here and not through the table.
    pub(crate) fn resolve_select(&mut self, key: u8) -> Resolution {
        // The escape is read like every other key: the arrow keys begin
        // with an escape byte, and the sequence is only a sequence when
        // its bytes are all there. The map itself holds the escape, so
        // the leave is one fact and not a rule in the program.
        let mut candidate = self.pending.clone();
        candidate.push(key);
        match self.hit(Context::Select, &candidate) {
            Hit::Exact(Action::Command(command)) => {
                self.cancel();
                Resolution::Command(command)
            }
            Hit::Partial(_) => {
                self.pending = candidate;
                Resolution::Pending
            }
            Hit::None => {
                self.cancel();
                Resolution::Ignore
            }
            Hit::Exact(Action::Map(_)) => {
                self.cancel();
                Resolution::Ignore
            }
        }
    }

    /// resolve_visual reads a key in VISUAL mode against the root map and the
    /// group a sequence opened.
    pub(crate) fn resolve_visual(&mut self, key: u8) -> Resolution {
        let map = self.group.unwrap_or(Context::Root);
        let mut candidate = self.pending.clone();
        candidate.push(key);
        match self.hit(map, &candidate) {
            Hit::Exact(Action::Command(command)) => {
                self.cancel();
                Resolution::Command(command)
            }
            Hit::Exact(Action::Map(context)) => {
                if context == Context::Select {
                    // The selection is a mode and not a group: the mode
                    // line says which mode stands, and the keys of the
                    // selection are read against the select map.
                    self.cancel();
                    return Resolution::Command(Command::EnterSelect);
                }
                // The group is open: the next key is read against it.
                self.group = Some(context);
                self.pending = candidate;
                Resolution::Pending
            }
            Hit::Partial(Action::Map(context)) => {
                self.group = Some(context);
                self.pending = candidate;
                Resolution::Pending
            }
            Hit::Partial(Action::Command(_)) => {
                self.pending = candidate;
                Resolution::Pending
            }
            Hit::None => {
                if self.pending.is_empty() {
                    return Resolution::Ignore;
                }
                // The sequence was wrong: drop it and try the key on its own,
                // so one wrong key never runs a command by accident.
                self.cancel();
                self.resolve_visual(key)
            }
        }
    }

    /// resolve_explorer reads a key in the EXPLORER against the map the
    /// explorer is showing.
    pub(crate) fn resolve_explorer(&mut self, key: u8) -> Resolution {
        if key == 0x1b {
            // Escape cancels the exploration: one level up, or out of it.
            if self.explorer != Context::Root {
                self.explorer = Context::Root;
                self.pending.clear();
                return Resolution::Map(Context::Root);
            }
            return Resolution::Command(Command::CloseExplorer);
        }
        let prefix = self.explorer.prefix();
        let mut candidate = prefix.to_vec();
        candidate.extend_from_slice(&self.pending);
        candidate.push(key);
        match self.hit(self.explorer, &candidate) {
            Hit::Exact(Action::Command(command)) => {
                self.pending.clear();
                Resolution::Command(command)
            }
            Hit::Exact(Action::Map(context)) => {
                self.pending.clear();
                Resolution::Map(context)
            }
            Hit::Partial(_) => {
                self.pending = candidate[prefix.len()..].to_vec();
                Resolution::Pending
            }
            Hit::None => {
                self.pending.clear();
                Resolution::Ignore
            }
        }
    }

    /// hit answers what a candidate matches in one map: exactly, as the start
    /// of a longer sequence, or not at all.
    pub(crate) fn hit(&self, map: Context, candidate: &[u8]) -> Hit {
        for binding in bindings(map) {
            if binding.bytes == candidate {
                return Hit::Exact(binding.action);
            }
        }
        for binding in bindings(map) {
            if binding.bytes.len() > candidate.len() && binding.bytes.starts_with(candidate) {
                return Hit::Partial(binding.action);
            }
        }
        Hit::None
    }
}

