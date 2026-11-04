use super::*;

impl Screen {
    pub fn empty(
        agent_program: String,
        editor_program: String,
        editor_mcp: Vec<String>,
    ) -> Screen {
        Screen {
            direction: "row".to_string(),
            tabs: Vec::new(),
            tab: 0,
            panes: Vec::new(),
            focused: 0,
            mode: Mode::Insert,
            command: String::new(),
            cols: 0,
            rows: 0,
            agent_program,
            editor_program,
            message: String::new(),
            events: Vec::new(),
            reserved: false,
            select: Selection::new(),
            ring: Vec::new(),
            keymap: Keymap::empty(),
            panel: None,
            git: None,
            git_want: String::new(),
            workspace: None,
            workspace_view: String::new(),
            workspace_name: String::new(),
            sessions_dir: String::new(),
            project_name: String::new(),
            level: 2,
            shows_tab_bar: true,
            workspace_quiet: false,
            editor_mcp,
            pending: None,
            fresh: false,
            pending_focus: None,
            watch: false,
        }
    }

}

