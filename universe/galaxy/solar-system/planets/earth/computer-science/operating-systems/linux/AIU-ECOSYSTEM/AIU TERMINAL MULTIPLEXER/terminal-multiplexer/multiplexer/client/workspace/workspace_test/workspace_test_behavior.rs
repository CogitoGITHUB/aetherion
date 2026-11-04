    use super::*;
    use serde_json::json;

    #[test]
    fn the_workspaces_are_one_line_each_with_their_projects() {
        let data = json!({
            "workspaces": [{
                "id": "w1",
                "name": "the work",
                "projects": [
                    { "id": "p1", "name": "the first", "roots": ["/src"], "tags": [] },
                    { "id": "p2", "name": "the second", "roots": [], "tags": [] }
                ],
                "context": { "project": "the first", "resources": [] }
            }],
            "workspace": "w1",
            "project": "the first"
        });
        let lines = lines("list", &data);
        assert!(lines[0].contains("the workspaces: 1"), "the count: {:?}", lines);
        assert!(lines[1].contains("w1") && lines[1].contains("the work"), "the workspace: {:?}", lines);
        assert!(lines.iter().any(|line| line.contains("the projects: 2")));
        assert!(lines.iter().any(|line| line.contains("the first") && line.contains("/src")));
        assert!(lines.iter().any(|line| line.contains("the project: the first")));
    }

    #[test]
    fn an_empty_workspace_says_so() {
        let data = json!({ "workspaces": [], "workspace": "", "project": "" });
        let lines = lines("list", &data);
        assert!(lines.iter().any(|line| line.contains("there is no workspace yet")));
        assert!(lines.iter().any(|line| line.contains("the project: none")));
    }

    #[test]
    fn the_context_view_names_the_project_and_its_resources() {
        let data = json!({
            "workspaces": [{
                "id": "w1",
                "name": "the work",
                "projects": [],
                "context": { "project": "the first", "resources": ["r1", "r2"] }
            }],
            "workspace": "w1",
            "project": "the first"
        });
        let lines = lines("context", &data);
        assert!(lines.iter().any(|line| line.contains("the workspace: the work")));
        assert!(lines.iter().any(|line| line.contains("the project: the first")));
        assert!(lines.iter().any(|line| line.contains("the resources: 2")));
        assert!(lines.iter().any(|line| line.trim() == "r1"));
    }
