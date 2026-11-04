use super::*;

impl Keymap {
    pub fn empty() -> Keymap {
        Keymap {
            pending: Vec::new(),
            group: None,
            explorer: Context::Root,
        }
    }

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

    #[cfg(test)]
    pub fn group(&self) -> Option<Context> {
        self.group
    }

    pub fn explorer_map(&self) -> Context {
        self.explorer
    }

    pub fn open_map(&mut self, context: Context) {
        self.explorer = context;
        self.pending.clear();
    }

    pub fn cancel(&mut self) {
        self.pending.clear();
        self.group = None;
    }

    pub fn resolve(&mut self, mode: Mode, key: u8) -> Resolution {
        match mode {
            Mode::Insert => Resolution::Pass,
            Mode::Command => Resolution::Pass,
            Mode::Visual => self.resolve_visual(key),
            Mode::Explorer => self.resolve_explorer(key),
            Mode::Select => self.resolve_select(key),
        }
    }

    pub(crate) fn resolve_select(&mut self, key: u8) -> Resolution {
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
                    self.cancel();
                    return Resolution::Command(Command::EnterSelect);
                }
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
                self.cancel();
                self.resolve_visual(key)
            }
        }
    }

    pub(crate) fn resolve_explorer(&mut self, key: u8) -> Resolution {
        if key == 0x1b {
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

