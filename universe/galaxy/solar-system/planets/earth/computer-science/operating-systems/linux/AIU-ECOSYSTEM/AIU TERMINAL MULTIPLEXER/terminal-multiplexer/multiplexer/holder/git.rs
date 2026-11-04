
use std::path::Path;

use git_inspection::command::Comparison;
use git_inspection::model;
use git_inspection::Git;
use serde_json::{json, Value};

pub struct Answer {
    pub ok: bool,
    pub data: Value,
}

pub fn read(directory: &Path, what: &str) -> Answer {
    let git = match Git::open(directory) {
        Ok(git) => git,
        Err(why) => {
            return Answer {
                ok: false,
                data: json!({ "why": why }),
            }
        }
    };
    let data = match what {
        "changed" => {
            let status = git.status();
            json!({ "status": status.to_json() })
        }
        "diff" => match git.diffs(Comparison::WorkingVsIndex) {
            Ok(files) => json!({
                "comparison": Comparison::WorkingVsIndex.name(),
                "files": files
                    .iter()
                    .map(|file| json!({
                        "path": file.path,
                        "hunks": file.hunks.iter().map(|hunk| json!({
                            "old-start": hunk.old_start,
                            "old-lines": hunk.old_lines,
                            "new-start": hunk.new_start,
                            "new-lines": hunk.new_lines,
                            "lines": hunk.lines.iter().map(|line| json!({
                                "kind": line.kind.name(),
                                "mark": line.kind.mark(),
                                "text": line.text,
                                "old-line": line.old_line,
                                "new-line": line.new_line,
                            })).collect::<Vec<Value>>(),
                        })).collect::<Vec<Value>>(),
                    }))
                    .collect::<Vec<Value>>(),
            }),
            Err(why) => {
                return Answer {
                    ok: false,
                    data: json!({ "why": why }),
                }
            }
        },
        "history" => match git.log(None) {
            Ok(commits) => json!({
                "commits": commits.iter().map(|commit| commit.to_json()).collect::<Vec<Value>>(),
            }),
            Err(why) => {
                return Answer {
                    ok: false,
                    data: json!({ "why": why }),
                }
            }
        },
        "branches" => json!({
            "branches": git.branches().iter().map(|branch| json!({
                "name": branch.name,
                "head": branch.head,
                "upstream": branch.upstream,
                "divergence": branch.divergence.name(),
                "ahead": branch.divergence.ahead(),
                "behind": branch.divergence.behind(),
                "is-head": branch.is_head,
            })).collect::<Vec<Value>>(),
        }),
        _ => {
            let status = git.status();
            let repository = git.repository();
            json!({
                "status": status.to_json(),
                "repository": match repository {
                    Ok(repository) => repository.to_json(),
                    Err(_) => json!({}),
                },
            })
        }
    };
    Answer { ok: true, data }
}

#[allow(dead_code)]
fn the_model_is_shared() -> &'static str {
    model::WorkingTree::Modified.mark()
}
