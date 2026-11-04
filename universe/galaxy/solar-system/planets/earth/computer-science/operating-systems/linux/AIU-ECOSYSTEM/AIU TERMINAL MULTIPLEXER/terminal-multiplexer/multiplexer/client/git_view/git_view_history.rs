use super::*;

/// diff answers the lines of the diff: which comparison, then the files
/// and the hunks and the lines that changed.
pub(crate) fn diff(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    if let Some(comparison) = text(data, "comparison") {
        lines.push(format!("  the comparison: {}", comparison));
    }
    for file in list(data, "files") {
        let path = text(&file, "path").unwrap_or_default();
        lines.push(format!("  {}", path));
        for hunk in list(&file, "hunks") {
            let old_start = number(&hunk, "old-start").unwrap_or(0);
            let old_lines = number(&hunk, "old-lines").unwrap_or(0);
            let new_start = number(&hunk, "new-start").unwrap_or(0);
            let new_lines = number(&hunk, "new-lines").unwrap_or(0);
            lines.push(format!(
                "    @@ -{},{} +{},{} @@",
                old_start, old_lines, new_start, new_lines
            ));
            for line in list(&hunk, "lines") {
                let mark = text(&line, "mark").unwrap_or_default();
                let body = text(&line, "text").unwrap_or_default();
                lines.push(format!("    {}{}", mark, body));
            }
        }
    }
    if lines.len() <= 1 {
        lines.push("  nothing differs".to_string());
    }
    lines
}

/// history answers the lines of the history: the commits, newest first.
pub(crate) fn history(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for commit in list(data, "commits") {
        let short = text(&commit, "short").unwrap_or_default();
        let summary = text(&commit, "summary").unwrap_or_default();
        let author = text(&commit, "author").unwrap_or_default();
        let date = text(&commit, "date").unwrap_or_default();
        lines.push(format!("  {}  {}", short, summary));
        lines.push(format!("       {}  {}", author, date));
        for file in list(&commit, "files") {
            lines.push(format!("       {}", file));
        }
    }
    if lines.is_empty() {
        lines.push("  the history is empty".to_string());
    }
    lines
}

/// branches answers the lines of the branches: the name, the upstream
/// and the distance, and a star on the one the head is on.
pub(crate) fn branches(data: &Value) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for branch in list(data, "branches") {
        let name = text(&branch, "name").unwrap_or_default();
        let upstream = text(&branch, "upstream").unwrap_or_default();
        let divergence = text(&branch, "divergence").unwrap_or_default();
        let head = branch
            .get("is-head")
            .and_then(|value| value.as_bool())
            .unwrap_or(false);
        let mut line = format!("  {} {:<20} {:<24} {}", if head { "*" } else { " " }, name, upstream, divergence);
        if let Some(ahead) = number(&branch, "ahead") {
            line.push_str(&format!("  ahead {}", ahead));
        }
        if let Some(behind) = number(&branch, "behind") {
            line.push_str(&format!("  behind {}", behind));
        }
        lines.push(line);
    }
    if lines.is_empty() {
        lines.push("  there are no branches".to_string());
    }
    lines
}

