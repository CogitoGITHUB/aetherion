    use super::*;
    use serde_json::json;

    #[test]
    fn a_changed_file_shows_the_two_marks_apart() {
        let data = json!({
            "status": {
                "counts": { "staged": 1, "unstaged": 1, "untracked": 0, "conflicted": 0 },
                "files": [
                    { "path": "a.txt", "index": "modified", "index-mark": "~",
                      "working": "modified", "working-mark": "~" },
                    { "path": "b.txt", "index": "unchanged", "index-mark": " ",
                      "working": "untracked", "working-mark": "?" }
                ]
            }
        });
        let lines = lines("changed", &data);
        assert!(lines[0].contains("1 staged"), "the counts are there: {:?}", lines);
        assert!(lines[1].contains("~~ a.txt"), "the marks are together: {:?}", lines);
        assert!(lines[1].contains("staged: modified"), "the words say it: {:?}", lines);
        assert!(lines[2].contains(" ? b.txt"), "the untracked mark is there: {:?}", lines);
    }

    #[test]
    fn an_unknown_upstream_is_not_shown_as_in_step() {
        let data = json!({
            "status": { "head": "main", "counts": {}, "files": [] },
            "repository": { "root": "/repo", "worktrees": [] }
        });
        let lines = lines("overview", &data);
        assert!(lines.iter().any(|line| line.contains("the branch: main")));
        assert!(
            !lines.iter().any(|line| line.contains("in step")),
            "nothing claims to be in step: {:?}",
            lines
        );
    }

    #[test]
    fn the_worktrees_are_one_line_each() {
        let data = json!({
            "status": { "head": "main", "counts": {}, "files": [] },
            "repository": {
                "root": "/repo",
                "worktrees": [
                    { "path": "/repo", "head": "main",
                      "counts": { "staged": 1, "unstaged": 0, "untracked": 0, "conflicted": 0 } },
                    { "path": "/repo/linked", "head": "side",
                      "counts": { "staged": 0, "unstaged": 2, "untracked": 0, "conflicted": 0 } }
                ]
            }
        });
        let lines = lines("overview", &data);
        assert!(lines.iter().any(|line| line.contains("/repo/linked") && line.contains("side")));
    }

    #[test]
    fn a_worktree_browser_names_every_worktree() {
        let data = json!({
            "repository": {
                "root": "/repo",
                "worktrees": [
                    { "path": "/repo", "head": "main", "detached": false,
                      "locked": false, "prunable": false,
                      "divergence": "in step with the upstream",
                      "counts": { "staged": 0, "unstaged": 1, "untracked": 0, "conflicted": 0 } },
                    { "path": "/repo/side", "head": "side", "detached": true,
                      "locked": true, "prunable": false,
                      "divergence": "no upstream",
                      "counts": { "staged": 2, "unstaged": 0, "untracked": 0, "conflicted": 0 } }
                ]
            }
        });
        let lines = lines("worktrees", &data);
        assert!(lines[0].contains("the worktrees: 2"), "the count: {:?}", lines);
        assert!(lines.iter().any(|line| line.contains("/repo/side") && line.contains("side")));
        assert!(lines.iter().any(|line| line.contains("detached")), "the detached one says so: {:?}", lines);
        assert!(lines.iter().any(|line| line.contains("locked")), "the locked one says so: {:?}", lines);
    }

    #[test]
    fn a_diff_says_which_comparison_it_is() {
        let data = json!({
            "comparison": "working tree against index",
            "files": [{
                "path": "a.txt",
                "hunks": [{
                    "old-start": 1, "old-lines": 1, "new-start": 1, "new-lines": 1,
                    "lines": [{ "kind": "added", "mark": "+", "text": "new" }]
                }]
            }]
        });
        let lines = lines("diff", &data);
        assert!(lines[0].contains("working tree against index"));
        assert!(lines.iter().any(|line| line.contains("+new")));
    }
