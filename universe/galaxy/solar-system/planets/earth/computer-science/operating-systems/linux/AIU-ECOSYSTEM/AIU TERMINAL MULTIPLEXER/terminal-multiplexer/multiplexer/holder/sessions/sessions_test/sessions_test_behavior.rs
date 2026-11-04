    use super::*;
    use std::path::PathBuf;

    fn a_scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-sessions-{}-{}", std::process::id(), name));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    #[test]
    fn a_name_of_one_path_segment_is_taken() {
        assert!(check_name("work").is_ok());
        assert!(check_name("aiu-multiplexer_2").is_ok());
    }

    #[test]
    fn a_name_that_is_a_path_is_refused_and_the_reason_named() {
        let why = check_name("a/b").unwrap_err();
        assert!(why.contains("path"), "the reason: {:?}", why);
        assert!(check_name("..").unwrap_err().contains("path"));
        assert!(check_name("").unwrap_err().contains("name"));
        assert!(check_name("-x").unwrap_err().contains("starts with"));
        assert!(check_name(".hidden").unwrap_err().contains("starts with"));
        assert!(check_name("two words").unwrap_err().contains("space"));
    }

    #[test]
    fn the_sessions_directory_is_the_state_directorys_parent() {
        let state = PathBuf::from("/tmp/sessions/work");
        assert_eq!(dir_of(&state), PathBuf::from("/tmp/sessions"));
        assert_eq!(name_of(&state), "work");
    }

    #[test]
    fn what_stands_is_the_directories_in_order_and_none_is_not_an_error() {
        let dir = a_scratch("list");
        assert!(stands(&dir).is_empty(), "nothing has been made");
        std::fs::create_dir_all(dir.join("b-session")).unwrap();
        std::fs::create_dir_all(dir.join("a-session")).unwrap();
        std::fs::write(dir.join("not-a-session"), "x").unwrap();
        assert_eq!(stands(&dir), vec!["a-session", "b-session"]);
    }

    #[test]
    fn a_socket_a_dead_holder_left_behind_is_not_a_holder() {
        let dir = a_scratch("stale");
        let session = dir.join("stale");
        std::fs::create_dir_all(&session).unwrap();
        let socket = session.join("holder.sock");
        let fd = super::super::bind(&socket).expect("the scratch socket is bound");
        let list = listing(&dir);
        let sessions = list["sessions"].as_array().cloned().unwrap_or_default();
        assert_eq!(sessions.len(), 1, "one session is listed");
        assert_eq!(sessions[0]["held"], false, "nothing answers behind it");
        super::super::close(fd);
        let _ = std::fs::remove_file(&socket);
    }

    #[test]
    fn a_session_with_no_socket_is_listed_as_not_held() {
        let dir = a_scratch("unheld");
        std::fs::create_dir_all(dir.join("gone")).unwrap();
        let list = listing(&dir);
        let sessions = list["sessions"].as_array().cloned().unwrap_or_default();
        assert_eq!(sessions.len(), 1, "one session is listed");
        assert_eq!(sessions[0]["session"], "gone");
        assert_eq!(sessions[0]["held"], false);
        assert!(sessions[0]["why"].as_str().unwrap_or("").contains("no holder"));
    }
