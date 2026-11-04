use super::*;

impl Screen {
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

    pub(super) fn open_agent(&mut self) -> Action {
        let program = self.agent_program.clone();
        let target = agent_name(&program);
        let pane = self.focused_pane();
        let why = format!("the owner asked for the agent beside the pane {}", pane);
        self.message = format!("the agent is opening with the context of {}", pane);
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

    pub(super) fn open_pane(&mut self, name: String, program: String, tab: String) -> Action {
        self.pending_focus = Some(name.clone());
        Action::Request(json!({
            "op": "open",
            "name": name,
            "program": program,
            "tab": tab
        }))
    }
}
