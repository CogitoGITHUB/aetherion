use super::*;

impl Screen {
    /// send_region asks the holder to send the region to the agents. The
    /// bundle is built by the holder, where the redaction seam is, and the
    /// agents that are open are the ones that receive it. The pane the
    /// region came from is named, so the holder can add that pane's command
    /// record to the bundle.
    pub(super) fn send_region(&mut self, lines: &[String]) -> Action {
        let text = self.select.region(lines);
        if text.is_empty() {
            self.message = "there is no region: the mark is not set".to_string();
            return Action::Nothing;
        }
        let program = self.agent_program.clone();
        let pane = self.focused_pane();
        self.message = "the region is on its way to the agents".to_string();
        Action::Request(json!({
            "op": "send-agent",
            "selection": text,
            "target": agent_name(&program),
            "from": pane,
            "why": "the owner sent the picked text to the agents",
        }))
    }

    /// agent_here asks the holder for an agent beside the focused pane,
    /// with the picked text in the bundle.
    pub(super) fn agent_here(&mut self, lines: &[String]) -> Action {
        let program = self.agent_program.clone();
        let target = agent_name(&program);
        let pane = self.focused_pane();
        let text = self.select.region(lines);
        let why = format!("the owner opened the agent beside the pane {}", pane);
        self.message = format!("the agent is opening with the picked text of {}", pane);
        Action::Request(json!({
            "op": "open",
            "name": "agent",
            "program": program,
            "tab": self.focused_tab(),
            "context": {
                "pane": pane,
                "target": target,
                "why": why,
                "selection": text,
            }
        }))
    }

    /// open_agent asks the holder for an agent pane beside the focused one,
    /// with the context of that pane attached: the shell output, the shell,
    /// the place and the why. Nothing is copied by hand.
    ///
    /// The context is the tail of the pane's log: the holder sends every
    /// record to the clients that watch it, so the screen already holds
    /// what the log holds.
    pub(super) fn open_agent(&mut self) -> Action {
        let program = self.agent_program.clone();
        let target = agent_name(&program);
        let pane = self.focused_pane();
        let why = format!("the owner asked for the agent beside the pane {}", pane);
        self.message = format!("the agent is opening with the context of {}", pane);
        // The context is the tail of that pane's log, and the log belongs to
        // the holder: the screen asks for the context and never copies it.
        Action::Request(json!({
            "op": "open",
            "name": "agent",
            "program": program,
            "tab": self.focused_tab(),
            "context": {
                "pane": pane,
                "target": target,
                "why": why,
            }
        }))
    }

    /// open_pane asks the holder for a pane with a program in it.
    pub(super) fn open_pane(&mut self, name: String, program: String, tab: String) -> Action {
        // The focus follows the pane the owner asked for, once the holder has
        // it: the answer is the state, and take_state moves the focus.
        self.pending_focus = Some(name.clone());
        Action::Request(json!({
            "op": "open",
            "name": name,
            "program": program,
            "tab": tab
        }))
    }
}
