    use super::*;
    use std::fs;

    /// scratch answers a state directory of this test's own, so two tests
    /// never write over each other's file.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-config-{}-{}", std::process::id(), name));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    #[test]
    fn the_defaults_are_level_two_with_the_tab_bar() {
        let config = Config::defaults();
        assert_eq!(config.level, 2);
        assert_eq!(config.tab_bar, true);
    }

    #[test]
    fn a_config_holds_the_level_and_the_tab_bar() {
        let config = Config::from_json("{\"level\": 0, \"tab-bar\": false}").expect("it parses");
        assert_eq!(config.level, 0);
        assert_eq!(config.tab_bar, false);
    }

    #[test]
    fn a_key_the_config_does_not_know_is_ignored() {
        let config =
            Config::from_json("{\"level\": 1, \"later\": true}").expect("it parses");
        assert_eq!(config.level, 1);
        assert_eq!(config.tab_bar, true);
    }

    #[test]
    fn a_level_above_three_is_a_reason_and_not_a_clamp() {
        let why = Config::from_json("{\"level\": 7}").expect_err("it is refused");
        assert!(why.contains("higher than 3"), "the reason says why: {}", why);
    }

    #[test]
    fn a_tab_bar_that_is_not_a_boolean_is_a_reason() {
        let why = Config::from_json("{\"tab-bar\": \"yes\"}").expect_err("it is refused");
        assert!(why.contains("true or false"), "the reason says why: {}", why);
    }

    #[test]
    fn a_config_is_written_the_way_it_is_read() {
        let dir = scratch("written");
        let path = dir.join("config.json");
        let written = Config {
            level: 3,
            tab_bar: false,
        };
        fs::write(&path, written.to_json().as_bytes()).expect("the file is written");
        let read = Config::read(&path).expect("it reads back");
        assert_eq!(read, written);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn with_no_file_at_all_the_built_in_defaults_answer() {
        let dir = scratch("empty");
        let named = dir.join("nothing-here.json");
        let config = ConfigFile::at(&dir, Some(named));
        assert_eq!(config.config(), &Config::defaults());
        assert_eq!(config.origin(), "the built-in defaults");
        assert_eq!(config.problem(), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_broken_file_at_the_start_falls_back_and_keeps_the_reason() {
        let dir = scratch("broken-start");
        let named = dir.join("config.json");
        fs::write(&named, b"{ not json").expect("the file is written");
        let config = ConfigFile::at(&dir, Some(named));
        assert_eq!(config.config(), &Config::defaults());
        let said = config.problem().unwrap_or("");
        assert!(said.contains("not used"), "the reason says why: {}", said);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_rewritten_file_is_a_change() {
        let dir = scratch("rewritten");
        let named = dir.join("config.json");
        fs::write(&named, b"{\"level\": 2, \"tab-bar\": true}").expect("the file is written");
        let mut config = ConfigFile::at(&dir, Some(named.clone()));
        assert!(matches!(config.reload_if_changed(), Reload::Unchanged));

        let next = Config {
            level: 0,
            tab_bar: false,
        };
        fs::write(&named, next.to_json().as_bytes()).expect("the file is rewritten");
        match config.reload_if_changed() {
            Reload::Changed(found) => assert_eq!(found, next),
            _ => panic!("the change was not seen"),
        }
        assert_eq!(config.config(), &next);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_broken_file_leaves_the_config_in_force_and_says_why() {
        let dir = scratch("broken-reload");
        let named = dir.join("config.json");
        fs::write(&named, b"{\"level\": 1}").expect("the file is written");
        let mut config = ConfigFile::at(&dir, Some(named.clone()));
        let before = config.config().clone();

        fs::write(&named, b"this is not json at all").expect("the file is rewritten");
        match config.reload_if_changed() {
            Reload::Broken(why) => assert!(why.contains("stays"), "the reason says so: {}", why),
            _ => panic!("the broken file was taken for a change"),
        }
        assert_eq!(config.config(), &before);
        // The same file is reported once, not on every turn of the loop.
        assert!(matches!(config.reload_if_changed(), Reload::Unchanged));
        let _ = fs::remove_dir_all(&dir);
    }
