    use super::*;

    #[test]
    fn a_line_that_names_a_credential_keeps_its_name_and_loses_its_value() {
        let redacted = redact_text("api_key = sk-1234567890");
        assert_eq!(redacted, "api_key [redacted]");
    }

    #[test]
    fn a_token_that_has_the_shape_of_one_is_hidden() {
        let redacted = redact_text("sk-abcdefghijklmnop");
        assert_eq!(redacted, "[redacted]");
    }

    #[test]
    fn an_ordinary_line_is_left_alone() {
        let redacted = redact_text("the build finished in 4 seconds");
        assert_eq!(redacted, "the build finished in 4 seconds");
    }

    #[test]
    fn every_line_of_a_pane_is_seen() {
        let redacted = redact_text("first line\npassword: hunter2\nlast line");
        // The seam keeps the name and drops the value, exactly as the
        // editor's seam does: the colon is the separator and it goes too.
        assert_eq!(
            redacted,
            "first line\npassword[redacted]\nlast line"
        );
    }

    #[test]
    fn a_marked_line_holds_no_secret_any_more() {
        assert!(carries_a_secret("export api_key=sk-abcdef"));
        assert!(!carries_a_secret("export api_key[redacted]"));
        assert!(!carries_a_secret("the build finished in 4 seconds"));
    }
