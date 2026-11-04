    use super::*;

    fn bundle() -> Bundle {
        Bundle::make(
            "aiu-multiplexer",
            "aiu-ecosystem",
            "opencode",
            "the build finished",
            "",
            "",
            "",
            "the owner asked for the agent beside this pane",
        )
        .expect("the bundle is made")
    }

    #[test]
    fn a_bundle_without_a_why_is_refused() {
        let refused = Bundle::make("aiu-multiplexer", "aiu-ecosystem", "opencode", "text", "", "", "", "  ");
        assert!(refused.is_none(), "a send without a reason is refused");
    }

    #[test]
    fn the_text_of_a_bundle_is_the_shape_the_editor_writes() {
        let text = bundle().text();
        let lines: Vec<&str> = text.split('\n').collect();
        assert_eq!(
            lines[0],
            "boundary: 1  program: aiu-multiplexer  project: aiu-ecosystem  target: opencode"
        );
        assert_eq!(
            lines[1],
            "why: the owner asked for the agent beside this pane"
        );
        assert_eq!(lines[2], "selection: the build finished");
        assert_eq!(lines.len(), 3, "the bundle says what is there: {}", text);
    }

    #[test]
    fn an_absent_part_stays_absent() {
        let document = bundle().document();
        let references = document.get("references").expect("the references are there");
        assert_eq!(references.as_array().expect("a list").len(), 1);
    }

    #[test]
    fn a_bundle_passes_the_redaction_seam() {
        let made = Bundle::make(
            "aiu-multiplexer",
            "aiu-ecosystem",
            "opencode",
            "password: hunter2",
            "",
            "",
            "",
            "the owner asked",
        )
        .expect("the bundle is made");
        assert!(!made.text().contains("hunter2"), "the secret left: {}", made.text());
        assert!(made.text().contains("[redacted]"), "the redaction is not marked");
    }

    #[test]
    fn the_command_record_travels_with_the_selection() {
        let made = bundle().carrying("ls -la", "total 0\ndrwxr-xr-x 2");
        let document = made.document();
        let references = document
            .get("references")
            .and_then(|value| value.as_array())
            .expect("the references are there");
        let keys: Vec<String> = references
            .iter()
            .filter_map(|reference| reference.as_object())
            .filter_map(|object| object.keys().next().cloned())
            .collect();
        assert_eq!(
            keys,
            vec!["selection", "command", "output"],
            "the record travels with the selection"
        );
        let text = made.text();
        assert!(text.contains("selection: the build finished"), "{}", text);
        assert!(text.contains("command: ls -la"), "{}", text);
        assert!(text.contains("output: total 0"), "{}", text);
    }

    #[test]
    fn the_command_record_passes_the_redaction_seam() {
        let made = bundle().carrying("export api_key=sk-abcdef", "sk-abcdef");
        let text = made.text();
        assert!(!text.contains("sk-abcdef"), "the secret left: {}", text);
        // The seam keeps the name and drops the value: the separator goes
        // with the value, exactly as it does for every other line.
        assert!(text.contains("command: export api_key[redacted]"), "{}", text);
        assert!(text.contains("output: [redacted]"), "{}", text);
    }

    #[test]
    fn a_bundle_without_a_command_record_says_nothing_of_one() {
        let text = bundle().text();
        assert!(!text.contains("command:"), "{}", text);
        assert!(!text.contains("output:"), "{}", text);
    }

    #[test]
    fn the_seam_answers_whether_a_text_would_change_on_its_way_out() {
        assert!(carries_no_secret("the build finished"));
        assert!(!carries_no_secret("password: hunter2"));
    }
