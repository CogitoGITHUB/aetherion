    use super::*;

    /// a_directory answers a directory of its own for the tests.
    fn a_directory(name: &str) -> std::path::PathBuf {
        let directory = std::env::temp_dir().join(name);
        let _ = std::fs::remove_dir_all(&directory);
        directory
    }

    #[test]
    fn an_empty_workspace_directory_holds_no_workspace() {
        let directory = a_directory("mux-workspace-empty");
        let answer = read(&directory, "", "list");
        assert!(answer.ok, "the engine answers: {}", answer.reason);
        assert_eq!(
            answer.data.get("workspaces").and_then(|held| held.as_array()).map(|held| held.len()),
            Some(0),
            "there is no workspace yet: {:?}",
            answer.data
        );
        let _ = std::fs::remove_dir_all(&directory);
    }

    #[test]
    fn a_workspace_and_its_project_are_held_after_the_change() {
        let directory = a_directory("mux-workspace-made");
        let created = write(&directory, "", "create", "the work");
        assert!(created.ok, "the workspace is made: {}", created.reason);
        let registered = write(&directory, "", "project", "the first");
        assert!(registered.ok, "the project is registered: {}", registered.reason);
        let held = read(&directory, "", "list");
        assert!(held.ok, "the workspace is read: {}", held.reason);
        let workspaces = list(&held.data, "workspaces");
        assert_eq!(workspaces.len(), 1, "one workspace: {:?}", held.data);
        let name = text(&workspaces[0], "name").unwrap_or_default();
        assert_eq!(name, "the work", "the workspace is named: {:?}", workspaces[0]);
        let projects = list(&workspaces[0], "projects");
        assert_eq!(projects.len(), 1, "one project: {:?}", workspaces[0]);
        let project = text(&projects[0], "name").unwrap_or_default();
        assert_eq!(project, "the first", "the project is named: {:?}", projects[0]);
        let _ = std::fs::remove_dir_all(&directory);
    }

    #[test]
    fn opening_a_project_puts_it_in_the_context() {
        let directory = a_directory("mux-workspace-context");
        assert!(write(&directory, "", "create", "the work").ok);
        assert!(write(&directory, "", "project", "the first").ok);
        let opened = write(&directory, "", "open", "the first");
        assert!(opened.ok, "the context is opened: {}", opened.reason);
        let held = read(&directory, "", "list");
        let project = text(&held.data, "project").unwrap_or_default();
        assert_eq!(project, "the first", "the context names it: {:?}", held.data);
        let _ = std::fs::remove_dir_all(&directory);
    }

    #[test]
    fn a_project_that_is_not_there_is_refused_by_name() {
        let directory = a_directory("mux-workspace-refused");
        assert!(write(&directory, "", "create", "the work").ok);
        let opened = write(&directory, "", "open", "not here");
        assert!(!opened.ok, "the engine refuses: {:?}", opened.data);
        assert!(
            opened.reason.contains("not here"),
            "the refusal names it: {}",
            opened.reason
        );
        let _ = std::fs::remove_dir_all(&directory);
    }
