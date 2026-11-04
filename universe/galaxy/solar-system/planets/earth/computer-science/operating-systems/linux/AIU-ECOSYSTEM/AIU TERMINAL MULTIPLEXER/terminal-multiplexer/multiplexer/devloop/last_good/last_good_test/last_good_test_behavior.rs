    use super::*;
    use std::fs;

    /// scratch answers a state directory of this test's own.
    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-last-good-{}-{}", std::process::id(), name));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    #[test]
    fn with_no_record_there_is_no_last_good() {
        let dir = scratch("none");
        assert_eq!(last_good(&dir), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_recorded_path_answers_as_the_last_good() {
        let dir = scratch("recorded");
        let baked = dir.join("baked").join("config.json");
        keep_last_good(&dir, &baked).expect("the record is written");
        assert_eq!(last_good(&dir), Some(baked));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_recorded_path_is_read_back_as_the_text_it_holds() {
        let dir = scratch("read-back");
        let baked = dir.join("baked").join("config.json");
        fs::create_dir_all(baked.parent().expect("the baked directory is under the state"))
            .expect("the baked directory is made");
        fs::write(&baked, b"{\"level\": 1}\n").expect("the bake is written");
        keep_last_good(&dir, &baked).expect("the record is written");
        let path = last_good(&dir).expect("there is a last good");
        let text = read_text(&path).expect("the recorded file reads back");
        assert_eq!(text, "{\"level\": 1}\n");
        let _ = fs::remove_dir_all(&dir);
    }
