
use serde_json::{json, Value};

#[path = "../redact/redact_hide.rs"]
mod redact;

pub const BOUNDARY: &str = "1";

pub struct Bundle {
    pub program: String,
    pub project: String,
    pub target: String,
    pub selection: String,
    pub command: String,
    pub output: String,
    pub file: String,
    pub position: String,
    pub address: String,
    pub why: String,
}

impl Bundle {
    pub fn make(
        program: &str,
        project: &str,
        target: &str,
        selection: &str,
        file: &str,
        position: &str,
        address: &str,
        why: &str,
    ) -> Option<Bundle> {
        if why.trim().is_empty() {
            return None;
        }
        Some(Bundle {
            program: program.to_string(),
            project: project.to_string(),
            target: target.to_string(),
            selection: redact::redact_text(selection),
            command: String::new(),
            output: String::new(),
            file: file.to_string(),
            position: position.to_string(),
            address: address.to_string(),
            why: why.to_string(),
        })
    }

    pub fn carrying(mut self, command: &str, output: &str) -> Bundle {
        self.command = redact::redact_text(command.trim_end());
        self.output = redact::redact_text(output.trim_end());
        self
    }

    pub fn header(&self) -> Value {
        json!({
            "boundary": BOUNDARY,
            "program": self.program,
            "project": self.project,
            "target": self.target,
        })
    }

    pub fn document(&self) -> Value {
        let mut references: Vec<Value> = Vec::new();
        if !self.file.is_empty() {
            references.push(json!({ "path": self.file }));
        }
        if !self.position.is_empty() {
            references.push(json!({ "position": self.position }));
        }
        if !self.address.is_empty() {
            references.push(json!({ "address": self.address }));
        }
        if !self.selection.is_empty() {
            references.push(json!({ "selection": self.selection }));
        }
        if !self.command.is_empty() {
            references.push(json!({ "command": self.command }));
        }
        if !self.output.is_empty() {
            references.push(json!({ "output": self.output }));
        }
        json!({
            "header": self.header(),
            "references": references,
        })
    }

    pub fn text(&self) -> String {
        let mut lines: Vec<String> = Vec::new();
        lines.push(format!(
            "boundary: {}  program: {}  project: {}  target: {}",
            BOUNDARY, self.program, self.project, self.target
        ));
        lines.push(format!("why: {}", self.why));
        if !self.file.is_empty() {
            lines.push(format!("path: {}", self.file));
        }
        if !self.position.is_empty() {
            lines.push(format!("position: {}", self.position));
        }
        if !self.address.is_empty() {
            lines.push(format!("address: {}", self.address));
        }
        if !self.selection.is_empty() {
            lines.push(format!("selection: {}", self.selection));
        }
        if !self.command.is_empty() {
            lines.push(format!("command: {}", self.command));
        }
        if !self.output.is_empty() {
            lines.push(format!("output: {}", self.output));
        }
        lines.join("\n")
    }
}

pub fn carries_no_secret(text: &str) -> bool {
    !redact::carries_a_secret(text)
}

#[cfg(test)]
#[path = "bundle_test/bundle_test_behavior.rs"]
mod tests;
