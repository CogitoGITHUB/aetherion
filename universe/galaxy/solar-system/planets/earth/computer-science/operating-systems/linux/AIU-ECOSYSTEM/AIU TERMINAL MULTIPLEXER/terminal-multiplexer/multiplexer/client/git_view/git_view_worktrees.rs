use super::*;

pub(crate) fn worktrees(data: &Value) -> Vec<String> {
    let repository = data.get("repository").cloned().unwrap_or(Value::Null);
    let held = list(&repository, "worktrees");
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("  the worktrees: {}", held.len()));
    for worktree in &held {
        let path = text(worktree, "path").unwrap_or_default();
        let head = text(worktree, "head").unwrap_or_default();
        let divergence = text(worktree, "divergence").unwrap_or_default();
        let detached = worktree
            .get("detached")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let locked = worktree
            .get("locked")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let prunable = worktree
            .get("prunable")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let mut line = format!("  {:<16} {:<34}", head, counts(worktree));
        if detached {
            line.push_str(" detached");
        }
        if !divergence.is_empty() {
            line.push_str(&format!("  {}", divergence));
        }
        if locked {
            line.push_str("  locked");
        }
        if prunable {
            line.push_str("  prunable");
        }
        lines.push(line);
        lines.push(format!("    {}", path));
    }
    if held.is_empty() {
        lines.push("  there are no worktrees".to_string());
    }
    lines
}

pub(crate) fn what_the_file_is(index: &str, working: &str) -> String {
    if working == "untracked" {
        return "untracked".to_string();
    }
    if index == "unchanged" {
        return format!("unstaged: {}", working);
    }
    if working == "clean" {
        return format!("staged: {}", index);
    }
    format!("staged: {}, unstaged: {}", index, working)
}

