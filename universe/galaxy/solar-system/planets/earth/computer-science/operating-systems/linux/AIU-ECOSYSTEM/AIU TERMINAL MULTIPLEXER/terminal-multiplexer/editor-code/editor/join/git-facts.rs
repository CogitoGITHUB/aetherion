
use std::path::{Path, PathBuf};

use git_inspection::command::Comparison;
use git_inspection::Git;

pub fn facts(file: &Path) -> Vec<(String, String)> {
    let file = std::fs::canonicalize(file).unwrap_or_else(|_| file.to_path_buf());
    let file = file.as_path();
    let directory = match file.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let git = match Git::open(&directory) {
        Ok(git) => git,
        Err(why) => {
            return vec![
                ("git-state".to_string(), "unknown".to_string()),
                ("git-why".to_string(), why),
            ]
        }
    };
    let status = git.status();
    let mut out: Vec<(String, String)> = Vec::new();
    out.push(("git-repository".to_string(), git.root().display().to_string()));
    out.push(("git-branch".to_string(), status.head.name()));
    out.push(("git-divergence".to_string(), status.divergence.name().to_string()));
    if let Some(ahead) = status.divergence.ahead() {
        out.push(("git-ahead".to_string(), ahead.to_string()));
    }
    if let Some(behind) = status.divergence.behind() {
        out.push(("git-behind".to_string(), behind.to_string()));
    }
    out.push(("git-staged".to_string(), status.counts.staged.to_string()));
    out.push(("git-unstaged".to_string(), status.counts.unstaged.to_string()));
    out.push(("git-untracked".to_string(), status.counts.untracked.to_string()));
    out.push(("git-conflicts".to_string(), status.counts.conflicted.to_string()));
    out.push(("git-freshness".to_string(), status.freshness.name().to_string()));
    let wanted = relative_to(git.root(), file);
    match status
        .files
        .iter()
        .find(|entry| entry.path == wanted)
    {
        Some(entry) => {
            out.push(("git-file".to_string(), entry.path.clone()));
            out.push(("git-file-index".to_string(), entry.index.name().to_string()));
            out.push(("git-file-working".to_string(), entry.working.name().to_string()));
        }
        None => {
            out.push(("git-file".to_string(), wanted));
            out.push(("git-file-index".to_string(), "unchanged".to_string()));
            out.push(("git-file-working".to_string(), "clean".to_string()));
        }
    }
    out
}

pub fn diff(file: &Path, asked: &str) -> Vec<(String, String)> {
    let comparison = match asked {
        "" | "unstaged" => Comparison::WorkingVsIndex,
        "staged" => Comparison::IndexVsHead,
        "all" => Comparison::WorkingVsHead,
        other => {
            return vec![
                ("git-diff-state".to_string(), "unknown".to_string()),
                (
                    "git-diff-why".to_string(),
                    format!(
                        "the comparison {} is not one of: unstaged, staged, all",
                        other
                    ),
                ),
            ]
        }
    };
    let file = std::fs::canonicalize(file).unwrap_or_else(|_| file.to_path_buf());
    let file = file.as_path();
    let directory = match file.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let git = match Git::open(&directory) {
        Ok(git) => git,
        Err(why) => {
            return vec![
                ("git-diff-state".to_string(), "unknown".to_string()),
                ("git-diff-why".to_string(), why),
            ]
        }
    };
    let wanted = relative_to(git.root(), file);
    let hunks = match git.diff(Some(&wanted), comparison) {
        Ok(hunks) => hunks,
        Err(why) => {
            return vec![
                ("git-diff-state".to_string(), "unknown".to_string()),
                ("git-diff-why".to_string(), why),
            ]
        }
    };
    let mut text = String::new();
    for hunk in &hunks {
        text.push_str(&format!(
            "@@ -{},{} +{},{} @@\n",
            hunk.old_start, hunk.old_lines, hunk.new_start, hunk.new_lines
        ));
        for line in &hunk.lines {
            text.push_str(line.kind.mark());
            text.push_str(&line.text);
            text.push('\n');
        }
    }
    vec![
        (
            "git-diff-comparison".to_string(),
            comparison.name().to_string(),
        ),
        ("git-diff-file".to_string(), wanted),
        ("git-diff-hunks".to_string(), hunks.len().to_string()),
        ("git-diff-text".to_string(), text),
    ]
}

pub fn history(file: &Path) -> Vec<(String, String)> {
    let file = std::fs::canonicalize(file).unwrap_or_else(|_| file.to_path_buf());
    let file = file.as_path();
    let directory = match file.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let git = match Git::open(&directory) {
        Ok(git) => git,
        Err(why) => {
            return vec![
                ("git-history-state".to_string(), "unknown".to_string()),
                ("git-history-why".to_string(), why),
            ]
        }
    };
    let commits = match git.log(None) {
        Ok(commits) => commits,
        Err(why) => {
            return vec![
                ("git-history-state".to_string(), "unknown".to_string()),
                ("git-history-why".to_string(), why),
            ]
        }
    };
    let mut text = String::new();
    for commit in &commits {
        text.push_str(&format!("{}  {}\n", commit.short, commit.summary));
        text.push_str(&format!("     {}  {}\n", commit.author, commit.date));
        for path in &commit.files {
            text.push_str(&format!("     {}\n", path));
        }
    }
    vec![
        ("git-history-count".to_string(), commits.len().to_string()),
        ("git-history-text".to_string(), text),
    ]
}

fn relative_to(root: &Path, file: &Path) -> String {
    let root = std::fs::canonicalize(root)
        .unwrap_or_else(|_| root.to_path_buf())
        .display()
        .to_string();
    let file = file.display().to_string();
    match file.strip_prefix(&root) {
        Some(rest) => rest.trim_start_matches('/').to_string(),
        None => file,
    }
}
