use super::*;

impl Screen {
    /// run does what the command says, and answers what the client must do
    /// with the holder. The command does not know which key asked for it.
    pub(super) fn run(&mut self, command: Command) -> Action {
        self.message = String::new();
        match command {
            Command::Nothing => Action::Nothing,
            Command::EnterInsert => {
                self.mode = Mode::Insert;
                self.message = "insert".to_string();
                Action::Nothing
            }
            Command::OpenCommandLine => {
                self.mode = Mode::Command;
                self.command.clear();
                Action::Nothing
            }
            Command::OpenExplorer => {
                self.mode = Mode::Explorer;
                self.keymap.open_map(Context::Root);
                self.show_explorer();
                Action::Nothing
            }
            Command::CloseExplorer => {
                self.close_panel();
                self.mode = Mode::Visual;
                Action::Nothing
            }
            Command::Detach => Action::Quit,
            Command::TabAdd => {
                let name = format!("tab-{}", self.tabs.len() + 1);
                let tab = name.clone();
                self.open_pane(name, "/bin/sh".to_string(), tab)
            }
            Command::TabClose => {
                let tab = self.focused_tab();
                Action::Request(json!({
                    "op": "close",
                    "kind": "tab",
                    "name": tab
                }))
            }
            Command::TabRename => {
                self.mode = Mode::Command;
                self.command = "tab rename ".to_string();
                Action::Nothing
            }
            Command::TabNext => {
                self.move_tab(1);
                Action::Nothing
            }
            Command::TabPrevious => {
                self.move_tab(-1);
                Action::Nothing
            }
            Command::PaneAdd => {
                let name = format!("pane-{}", self.panes.len() + 1);
                let tab = self.focused_tab();
                self.open_pane(name, "/bin/sh".to_string(), tab)
            }
            Command::PaneClose => {
                let pane = self.focused_pane();
                Action::Request(json!({
                    "op": "close",
                    "kind": "pane",
                    "name": pane
                }))
            }
            Command::PaneRename => {
                self.mode = Mode::Command;
                self.command = "pane rename ".to_string();
                Action::Nothing
            }
            Command::PaneNext => {
                self.move_focus(1);
                Action::Nothing
            }
            Command::PanePrevious => {
                self.move_focus(-1);
                Action::Nothing
            }
            Command::PaneGrow => self.change_weight(1),
            Command::PaneShrink => self.change_weight(-1),
            Command::OpenAgent => self.open_agent(),
            Command::OpenEditor => {
                let program = self.editor_program.clone();
                self.open_pane("editor".to_string(), program, self.focused_tab())
            }
            Command::ShowRecords => {
                self.show_records();
                Action::Nothing
            }
            Command::ShowSessions => self.show_sessions(),
            Command::GitOverview => self.show_git("overview"),
            Command::GitChanged => self.show_git("changed"),
            Command::GitDiff => self.show_git("diff"),
            Command::GitHistory => self.show_git("history"),
            Command::GitBranches => self.show_git("branches"),
            Command::GitWorktrees => self.show_git("worktrees"),
            Command::LevelHide => {
                // One level less: at level 1 the mode row and the tab bar
                // go too, and the panes take the whole screen.
                self.level = self.level.saturating_sub(1);
                self.message = format!("the level: {}", self.level);
                Action::Nothing
            }
            Command::LevelShow => {
                self.level = (self.level + 1).min(3);
                self.message = format!("the level: {}", self.level);
                Action::Nothing
            }
            Command::PageUp => {
                // The wheel is refused: there is no mouse here, so the
                // scroll is a key, and this is that key.
                if self.scroll_view(true) {
                    self.message = format!(
                        "the view is one page up: {} lines from the tail",
                        self.scroll_distance()
                    );
                } else {
                    self.message = "the view is at the oldest page: it did not move".to_string();
                }
                Action::Nothing
            }
            Command::PageDown => {
                if self.scroll_view(false) {
                    self.message = format!(
                        "the view is one page down: {} lines from the tail",
                        self.scroll_distance()
                    );
                } else {
                    self.message = "the view is at the newest words: it did not move".to_string();
                }
                Action::Nothing
            }
            Command::WorkspaceList => self.show_workspace("list"),
            Command::WorkspaceContext => self.show_workspace("context"),
            Command::AskEditor => {
                // The editor is asked through its own server, and the ask
                // takes as long as the editor takes to start. The owner is
                // told that before the wait, never after it.
                self.message =
                    "the editor is being asked: its own server starts first, and that takes a while"
                        .to_string();
                Action::AskEditor
            }
            Command::WorkspaceOpen => {
                // The owner names the project, and the name follows in the
                // command line.
                self.mode = Mode::Command;
                self.command = "workspace open ".to_string();
                Action::Nothing
            }
            Command::EnterSelect => {
                self.mode = Mode::Select;
                self.select = Selection::new();
                self.message = "the selection is open on the focused pane".to_string();
                Action::Nothing
            }
            Command::SelectLeft
            | Command::SelectRight
            | Command::SelectUp
            | Command::SelectDown
            | Command::SelectWordLeft
            | Command::SelectWordRight
            | Command::SelectMark
            | Command::SelectPopMark
            | Command::SelectCopy
            | Command::SelectCopyLine
            | Command::SelectCopyOut
            | Command::SelectSend
            | Command::SelectAgentHere
            | Command::PasteClipboard
            | Command::LeaveSelect => self.select_command(command),
        }
    }

    /// run_command runs the words the owner typed on the command line.
    pub(super) fn run_command(&mut self, said: &str) -> Action {
        let words: Vec<&str> = said.split_whitespace().collect();
        self.message = String::new();
        match words.as_slice() {
            [] => Action::Nothing,
            ["q"] | ["quit"] => Action::Quit,
            ["help"] => {
                self.mode = Mode::Explorer;
                self.keymap.open_map(Context::Root);
                self.show_explorer();
                Action::Nothing
            }
            ["mode", "visual"] => {
                self.mode = Mode::Visual;
                Action::Nothing
            }
            ["mode", "insert"] => {
                self.mode = Mode::Insert;
                Action::Nothing
            }
            ["tab", "new"] => self.run(Command::TabAdd),
            ["tab", "close"] => self.run(Command::TabClose),
            ["tab", "rename", name] => Action::Request(json!({
                "op": "rename",
                "kind": "tab",
                "name": self.focused_tab(),
                "to": name
            })),
            ["tab", "next"] => self.run(Command::TabNext),
            ["tab", "previous"] => self.run(Command::TabPrevious),
            ["pane", "new"] => self.run(Command::PaneAdd),
            ["pane", "close"] => self.run(Command::PaneClose),
            ["pane", "kill"] => { let pane = self.focused_pane(); self.message = format!("the pane {} will be killed for good", pane); Action::Request(json!({ "op": "kill", "name": pane })) }
            ["pane", "rename", name] => Action::Request(json!({
                "op": "rename",
                "kind": "pane",
                "name": self.focused_pane(),
                "to": name
            })),
            ["pane", "next"] => self.run(Command::PaneNext),
            ["pane", "previous"] => self.run(Command::PanePrevious),
            ["pane", "grow"] => self.run(Command::PaneGrow),
            ["pane", "shrink"] => self.run(Command::PaneShrink),
            ["workspace"] => self.run(Command::WorkspaceList),
            ["workspace", "context"] => self.run(Command::WorkspaceContext),
            ["workspace", "open", name] => Action::Request(json!({
                "op": "workspace",
                "what": "open",
                "name": name
            })),
            ["workspace", "create", name] => Action::Request(json!({
                "op": "workspace",
                "what": "create",
                "name": name
            })),
            ["workspace", "project", name] => Action::Request(json!({
                "op": "workspace",
                "what": "project",
                "name": name
            })),
            ["agent"] => self.run(Command::OpenAgent),
            ["editor"] => self.run(Command::OpenEditor),
            ["records"] => self.run(Command::ShowRecords),
            ["sessions"] => self.run(Command::ShowSessions),
            ["session", "create", name] => self.session_word("create", name),
            ["session", "rename", name] => self.session_word("rename", name),
            ["session", "kill", name] => self.session_word("kill", name),
            ["session", "switch", name] => self.switch_to(name),
            ["scroll", "up"] => self.run(Command::PageUp),
            ["scroll", "down"] => self.run(Command::PageDown),
            ["copy", pane, first, last] => {
                // The lines of a pane, counted from one: the view shows the
                // count, so the owner and the agent name the same line.
                self.copy_lines(pane, first, last);
                Action::Nothing
            }
            ["paste", "agent"] => self.paste_to_agent(),
            ["paste", pane] => self.paste_into(pane),
            ["clipboard", "out"] => {
                // The pick, and nothing else: the command line never takes a
                // region the point did not mark.
                let lines = self.select_lines();
                self.copy_out(&lines)
            }
            ["clipboard", "in"] => self.paste_clipboard(),
            ["rewind", pane, seq] => self.rewind_to(pane, seq),
            ["focus", pane] => {
                self.focus_pane(pane);
                Action::Nothing
            }
            ["view"] => Action::Nothing,
            other => {
                self.message = format!("{} is not a command", other.join(" "));
                Action::Nothing
            }
        }
    }
}
