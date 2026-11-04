use super::*;

pub fn lines(want: &str, data: &Value) -> Vec<String> {
    match want {
        "changed" => changed(data),
        "worktrees" => worktrees(data),
        "diff" => diff(data),
        "history" => history(data),
        "branches" => branches(data),
        _ => overview(data),
    }
}

pub(crate) fn overview(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    let status = data.get("status").cloned().unwrap_or(Value::Null);
    let repository = data.get("repository").cloned().unwrap_or(Value::Null);
    if let Some(root) = text(&repository, "root") {
        lines.push(format!("  the repository: {}", root));
    }
    let head = text(&status, "head").unwrap_or_default();
    let upstream = text(&status, "upstream");
    let mut branch_line = format!("  the branch: {}", head);
    if let Some(upstream) = upstream {
        branch_line.push_str(&format!("  of {}", upstream));
    }
    let ahead = number(&status, "ahead");
    let behind = number(&status, "behind");
    match (ahead, behind) {
        (Some(ahead), Some(behind)) => {
            branch_line.push_str(&format!("  ahead {}, behind {}", ahead, behind))
        }
        (Some(ahead), None) => branch_line.push_str(&format!("  ahead {}", ahead)),
        (None, Some(behind)) => branch_line.push_str(&format!("  behind {}", behind)),
        (None, None) => {}
    }
    lines.push(branch_line);
    lines.push(format!(
        "  the changes: {}",
        counts(&status)
    ));
    if let Some(fresh) = text(&status, "freshness") {
        lines.push(format!("  the state: {}", fresh));
    }
    let worktrees = list(&repository, "worktrees");
    lines.push(format!("  the worktrees: {}", worktrees.len()));
    for worktree in worktrees {
        let path = text(&worktree, "path").unwrap_or_default();
        let head = text(&worktree, "head").unwrap_or_default();
        lines.push(format!(
            "    {:<40} {:<20} {}",
            path,
            head,
            counts(&worktree)
        ));
    }
    lines
}

pub(crate) fn changed(data: &Value) -> Vec<String> {
    let status = data.get("status").cloned().unwrap_or(Value::Null);
    let mut lines: Vec<String> = Vec::new();
    lines.push(format!("  {}", counts(&status)));
    for file in list(&status, "files") {
        let path = text(&file, "path").unwrap_or_default();
        let staged = text(&file, "index-mark").unwrap_or_default();
        let unstaged = text(&file, "working-mark").unwrap_or_default();
        let working = text(&file, "working").unwrap_or_default();
        let index = text(&file, "index").unwrap_or_default();
        lines.push(format!(
            "  {}{} {:<40} {}",
            staged, unstaged, path, what_the_file_is(&index, &working)
        ));
    }
    lines
}

