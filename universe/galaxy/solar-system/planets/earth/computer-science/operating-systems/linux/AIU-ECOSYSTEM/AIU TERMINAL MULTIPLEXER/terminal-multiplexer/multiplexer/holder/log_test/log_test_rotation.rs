    use super::*;

    fn a_scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("mux-log-{}-{}", std::process::id(), name));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("the scratch directory is made");
        dir
    }

    fn a_record(seq: u64, text: &str) -> serde_json::Value {
        serde_json::json!({ "seq": seq, "kind": "progress", "outputs": { "text": text } })
    }

    #[test]
    fn a_log_is_the_owners_alone() {
        let dir = a_scratch("private");
        let path = dir.join("events.log");
        let mut log = Log::open(&path).unwrap();
        log.append(&a_record(1, "one")).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "the log is 0600: {:o}", mode);
    }

    #[test]
    fn a_state_directory_is_the_owners_alone() {
        let dir = a_scratch("dir").join("session");
        private_dir(&dir).unwrap();
        let mode = std::fs::metadata(&dir).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o700, "the directory is 0700: {:o}", mode);
    }

    #[test]
    fn a_loose_file_is_made_private_when_the_log_opens_it() {
        let dir = a_scratch("loose");
        let path = dir.join("events.log");
        std::fs::write(&path, "").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        let _log = Log::open(&path).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "the old file is made private: {:o}", mode);
    }

    #[test]
    fn the_rule_trims_to_the_newest_records_and_says_what_it_let_go() {
        let dir = a_scratch("trim");
        let path = dir.join("events.log");
        let mut log = Log::open_with(&path, 260, 3).unwrap();
        for seq in 1..=10 {
            log.append(&a_record(seq, "x")).unwrap();
        }
        assert!(log.over_limit(), "ten records pass a limit of 260 bytes");
        let trimmed = log.trim().unwrap();
        assert_eq!(trimmed.dropped, 8, "eight are let go");
        assert_eq!(trimmed.kept, 2, "two are kept: the bound, not the count, decides");
        assert_eq!(trimmed.from, 9, "the kept part starts at seq 9");
        assert_eq!(trimmed.to, 8, "and the let-go part ends at seq 8");
        let held = Log::records(&path).unwrap();
        assert_eq!(held.len(), 2, "the file holds two records");
        assert_eq!(held.first().unwrap()["seq"], 9, "the newest two");
        assert_eq!(held.last().unwrap()["seq"], 10);
        assert!(!log.over_limit(), "the trimmed log is under the rule again");
    }

    #[test]
    fn a_trim_writes_no_half_record_and_no_second_file_is_left() {
        let dir = a_scratch("whole");
        let path = dir.join("events.log");
        let mut log = Log::open_with(&path, 200, 10).unwrap();
        for seq in 1..=6 {
            log.append(&a_record(seq, "one line")).unwrap();
        }
        log.trim().unwrap();
        let body = std::fs::read_to_string(&path).unwrap();
        assert!(body.ends_with('\n'), "the last record is whole");
        for line in body.lines() {
            assert!(
                serde_json::from_str::<serde_json::Value>(line).is_ok(),
                "every line is a record: {:?}",
                line
            );
        }
        assert!(
            !path.with_extension("log.new").exists(),
            "the file beside the log is gone"
        );
    }

    #[test]
    fn one_record_bigger_than_the_bound_is_refused_and_not_retried() {
        let dir = a_scratch("huge");
        let path = dir.join("events.log");
        let mut log = Log::open_with(&path, 40, 2).unwrap();
        log.append(&a_record(1, "x")).unwrap();
        assert!(log.over_limit(), "one record of 49 bytes passes a bound of 40");
        let why = log.trim().unwrap_err();
        assert!(
            why.contains("cannot be trimmed under it"),
            "the refusal names the rule: {:?}",
            why
        );
        assert!(!log.over_limit(), "the rule is said once and not retried");
        assert_eq!(Log::records(&path).unwrap().len(), 1, "nothing was lost");
    }

    #[test]
    fn a_session_log_under_the_rule_is_never_trimmed() {
        let dir = a_scratch("under");
        let path = dir.join("events.log");
        let mut log = Log::open(&path).unwrap();
        for seq in 1..=50 {
            log.append(&a_record(seq, "a short line")).unwrap();
        }
        assert!(!log.over_limit(), "fifty short records are far under 4 MiB");
        assert_eq!(Log::records(&path).unwrap().len(), 50, "every record is held");
        assert_eq!(log.rule().0, LIMIT_BYTES, "the shipped rule is the one in force");
    }
