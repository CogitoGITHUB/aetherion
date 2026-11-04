    use super::*;
    use std::fs;

    /// scratch answers a state directory of this test's own.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-bake-{}-{}", std::process::id(), name));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    #[test]
    fn a_good_bake_is_written_and_becomes_the_last_good() {
        let dir = scratch("good");
        let config = Config {
            level: 3,
            tab_bar: false,
        };
        let baked = bake(&dir, &config);
        assert_eq!(baked.good, true);
        assert_eq!(baked.reason, None);
        assert_eq!(baked.last_good, Some(baked.path.clone()));
        assert_eq!(last_good::last_good(&dir), Some(baked.path.clone()));

        let text = last_good::read_text(&baked.path).expect("the baked file reads");
        assert_eq!(Config::from_json(&text).expect("it parses"), config);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_baked_file_says_it_was_generated() {
        let dir = scratch("generated");
        let baked = bake(&dir, &Config::defaults());
        let text = last_good::read_text(&baked.path).expect("the baked file reads");
        assert!(text.contains("generated-by"), "the file says so: {}", text);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_second_good_bake_takes_the_last_good() {
        let dir = scratch("second");
        let first = bake(&dir, &Config::defaults());
        let second = bake(
            &dir,
            &Config {
                level: 0,
                tab_bar: false,
            },
        );
        assert_eq!(first.path, second.path);
        assert_eq!(second.good, true);
        assert_eq!(last_good::last_good(&dir), Some(second.path));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_config_that_does_not_parse_is_not_baked() {
        let dir = scratch("refused");
        let good = bake(&dir, &Config::defaults());
        assert_eq!(good.good, true);
        let before = last_good::read_text(&good.path).expect("the bake reads");

        let source = dir.join("broken.json");
        fs::write(&source, b"{ nope").expect("the broken file is written");
        let refused = bake_file(&dir, &source);
        assert_eq!(refused.good, false);
        let why = refused.reason.unwrap_or_default();
        assert!(why.contains("does not hold a config"), "the reason says why: {}", why);
        assert_eq!(refused.last_good, Some(good.path.clone()));

        let after = last_good::read_text(&good.path).expect("the bake still reads");
        assert_eq!(before, after);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_report_says_what_the_bake_did() {
        let dir = scratch("report");
        let baked = bake(&dir, &Config::defaults());
        let lines = baked.report();
        assert!(lines[0].contains("the baked defaults"), "the path comes first: {:?}", lines);
        assert!(lines[1].starts_with("good:"), "the verdict comes next: {:?}", lines);
        assert!(lines[2].contains("the last good is now"), "the record comes last: {:?}", lines);
        let _ = fs::remove_dir_all(&dir);
    }
