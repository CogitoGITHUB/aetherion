    use super::*;
    use serde_json::json;

    #[test]
    fn every_op_that_changes_is_refused_by_name() {
        for op in THE_OPS_THAT_CHANGE {
            let why = refusal(&json!({ "op": op })).expect("a change is refused");
            assert!(why.contains(op), "the refusal names the op: {:?}", why);
            assert!(why.contains("watches the session"), "the rule is said: {:?}", why);
        }
    }

    #[test]
    fn the_reads_are_free() {
        for op in [
            "state", "read", "git", "workspace", "editor", "rewind", "sessions",
            "detach", "control-result",
        ] {
            assert!(refusal(&json!({ "op": op })).is_none(), "{} is a read", op);
        }
    }

    #[test]
    fn a_session_show_is_a_read_and_the_rest_is_a_change() {
        assert!(refusal(&json!({ "op": "session", "what": "show" })).is_none());
        for what in ["create", "rename", "kill"] {
            let why = refusal(&json!({ "op": "session", "what": what }))
                .expect("a session change is refused");
            assert!(why.contains(what), "the refusal names the what: {:?}", why);
        }
    }

    #[test]
    fn a_request_with_no_op_is_not_refused_here() {
        // The dispatch itself answers an unknown op; this predicate only
        // refuses what a watcher may not do.
        assert!(refusal(&json!({ "client": "a watcher" })).is_none());
    }
