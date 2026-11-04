    use super::pane_text_at;
    use serde_json::json;

    /// a_log is a journal of three panes' words: two panes say one line each,
    /// in the order the session recorded them.
    fn a_log() -> Vec<serde_json::Value> {
        vec![
            json!({ "seq": 1, "who": "work", "outputs": { "text": "the first line" } }),
            json!({ "seq": 2, "who": "notes", "outputs": { "text": "another pane" } }),
            json!({ "seq": 3, "who": "work", "outputs": { "text": "the second line" } }),
            json!({ "seq": 4, "who": "work", "outputs": { "text": "the third line" } }),
        ]
    }

    #[test]
    fn a_rewind_answers_the_lines_of_that_pane_up_to_the_chosen_record() {
        let held = a_log();
        let lines = pane_text_at(&held, "work", 3, 200);
        assert_eq!(lines, vec!["the first line", "the second line"]);
    }

    #[test]
    fn a_rewind_never_takes_a_record_after_the_one_chosen() {
        let held = a_log();
        let lines = pane_text_at(&held, "work", 1, 200);
        assert_eq!(lines, vec!["the first line"], "nothing of seq 3 or 4");
    }

    #[test]
    fn a_rewind_keeps_the_newest_lines_when_the_page_is_full() {
        let held = a_log();
        let lines = pane_text_at(&held, "work", 4, 1);
        assert_eq!(lines, vec!["the third line"], "the newest line of the page");
    }

    #[test]
    fn a_rewind_of_a_pane_that_said_nothing_answers_nothing() {
        let held = a_log();
        assert!(pane_text_at(&held, "nowhere", 4, 200).is_empty());
    }
