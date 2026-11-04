    use super::*;

    fn a_screen() -> Screen {
        let mut screen = Screen::empty("opencode".to_string(), "editor".to_string(), Vec::new());
        screen.cols = 60;
        screen.rows = 12;
        screen.tabs = vec!["main".to_string()];
        screen.panes = vec![PaneView {
            name: "work".to_string(),
            tab: "main".to_string(),
            weight: 1,
            lines: Vec::new(),
            scroll: 0,
        }];
        screen
    }

    #[test]
    fn the_config_sets_the_level_and_the_tab_bar() {
        let mut screen = a_screen();
        screen.set_level(0);
        screen.set_tab_bar(false);
        assert_eq!(screen.level(), 0);
        assert_eq!(screen.tab_bar_on(), false);
        let drawing = screen.draw();
        assert!(drawing.contains("VISUAL") == false, "no mode row: {:?}", drawing);
        assert!(drawing.contains("[main]") == false, "no tab bar: {:?}", drawing);
    }

    #[test]
    fn a_pane_the_owner_asked_for_takes_the_focus_when_the_state_arrives() {
        let mut screen = a_screen();
        screen.pending_focus = Some("pane-2".to_string());
        screen.take_state(&json!({
            "outputs": {
                "session": "mux--bin-sh-1",
                "tabs": ["main"],
                "panes": [
                    { "name": "main", "tab": "main", "weight": 1, "lines": [], "scroll": 0 },
                    { "name": "pane-2", "tab": "main", "weight": 1, "lines": [], "scroll": 0 }
                ]
            }
        }));
        assert_eq!(screen.focused_pane(), "pane-2", "the new pane is where the owner types");
        assert_eq!(screen.pending_focus, None, "the ask is spent");
    }

    #[test]
    fn a_level_above_three_is_taken_as_three() {
        let mut screen = a_screen();
        screen.set_level(9);
        assert_eq!(screen.level(), 3);
    }

    #[test]
    fn the_tab_bar_can_be_off_while_the_mode_row_stays() {
        let mut screen = a_screen();
        screen.set_level(2);
        screen.set_tab_bar(false);
        let drawing = screen.draw();
        assert!(drawing.contains("VISUAL"), "the mode row stays: {:?}", drawing);
        assert!(drawing.contains("[main]") == false, "the tab bar is gone: {:?}", drawing);
    }

    fn a_screen_with_words() -> Screen {
        let mut screen = a_screen();
        screen.panes[0].lines = (1..=40).map(|at| format!("line {}", at)).collect();
        screen
    }

    #[test]
    fn the_page_key_scrolls_the_view_to_the_older_words() {
        let mut screen = a_screen_with_words();
        let before = screen.window(0, 6);
        assert_eq!(before.first(), Some(&"line 35".to_string()));
        assert!(screen.scroll_view(true), "the view moved");
        let after = screen.window(0, 6);
        assert_eq!(after.first(), Some(&"line 29".to_string()));
        assert_eq!(after.last(), Some(&"line 34".to_string()));
    }

    #[test]
    fn the_view_stops_at_the_oldest_page() {
        let mut screen = a_screen_with_words();
        let mut moved = true;
        let mut pages = 0;
        while moved {
            moved = screen.scroll_view(true);
            if moved {
                pages = pages + 1;
            }
        }
        assert!(pages > 0, "the view moved at least once");
        assert_eq!(screen.scroll_distance(), 34);
        let oldest = screen.window(0, 6);
        assert_eq!(oldest.first(), Some(&"line 1".to_string()));
    }

    #[test]
    fn the_pick_restarts_over_the_fresh_text() {
        let mut screen = a_screen_with_words();
        screen.mode = Mode::Select;
        screen.select.right(&screen.select_lines());
        screen.select.set_mark();
        assert!(screen.select.mark().is_some(), "the mark stands");
        assert!(screen.scroll_view(true), "the view moved");
        screen.select.restart();
        assert_eq!(screen.select.point, (0, 0));
        assert!(screen.select.mark().is_none(), "the mark is gone");
    }

    fn a_picked_screen(width: usize) -> Screen {
        let mut screen = a_screen();
        let text: String = "x".repeat(width);
        screen.panes[0].lines = vec![text];
        screen.mode = Mode::Select;
        screen.select.set_mark();
        screen.select.point = (0, width);
        screen
    }

    #[test]
    fn the_pick_goes_out_to_the_android_clipboard_as_one_sequence() {
        let mut screen = a_picked_screen(11);
        let action = screen.run(Command::SelectCopyOut);
        let bytes = match action {
            Action::Terminal(bytes) => bytes,
            _ => panic!("the copy out writes the terminal"),
        };
        let said = String::from_utf8(bytes).unwrap();
        assert!(said.starts_with("\x1b]52;c;"), "the OSC 52 prefix: {:?}", said);
        assert!(said.ends_with('\x07'), "the bell ends it: {:?}", said);
        assert_eq!(
            screen.ring.first(),
            Some(&"xxxxxxxxxxx".to_string()),
            "the ring holds the same pick"
        );
        assert!(screen.message.contains("clipboard"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_pick_over_the_limit_is_refused_by_name_and_the_ring_keeps_it() {
        let mut screen = a_picked_screen(7000);
        let action = screen.run(Command::SelectCopyOut);
        assert!(matches!(action, Action::Nothing), "nothing goes to the terminal");
        assert!(screen.message.contains("8192"), "the limit: {:?}", screen.message);
        assert_eq!(screen.ring.len(), 1, "the owner's own copy is not lost");
    }

    #[test]
    fn an_empty_android_clipboard_is_said_and_nothing_is_sent() {
        let mut screen = a_screen();
        let action = screen.paste_text(String::new());
        assert!(matches!(action, Action::Nothing), "nothing is sent");
        assert!(screen.message.contains("empty"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_paste_over_the_limit_is_refused_with_the_numbers() {
        let mut screen = a_screen();
        let action = screen.paste_text("x".repeat(clipboard::PASTE_MAX + 1));
        assert!(matches!(action, Action::Nothing), "nothing is sent");
        assert!(screen.message.contains("65536"), "the limit: {:?}", screen.message);
    }

    #[test]
    fn a_session_word_asks_the_holder_for_that_command() {
        let mut screen = a_screen();
        let action = screen.run_command("session create second");
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "session");
                assert_eq!(request["what"], "create");
                assert_eq!(request["name"], "second");
            }
            _ => panic!("a session word is one request"),
        }
    }

    #[test]
    fn a_switch_needs_the_sessions_directory_the_holder_named() {
        let mut screen = a_screen();
        let action = screen.run_command("session switch second");
        assert!(matches!(action, Action::Nothing), "nothing is switched yet");
        assert!(screen.message.contains("did not say"), "the line: {:?}", screen.message);
        screen.sessions_dir = "/tmp/opencode/sessions".to_string();
        let action = screen.run_command("session switch second");
        match action {
            Action::Switch(name) => assert_eq!(name, "second"),
            _ => panic!("the switch is its own action"),
        }
    }

    #[test]
    fn a_session_name_with_a_slash_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("session kill a/b");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("not a session name"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_contract_refusal_is_answered_in_both_versions_and_what_to_do() {
        let record = json!({
            "kind": "fail",
            "who": "holder",
            "what": "the client and the holder do not agree on the contract",
            "inputs": {
                "client-event-contract": "event-log-format/1",
                "client-holder-contract": "multiplexer-holder/1"
            },
            "outputs": {
                "holder-event-contract": "event-log-format/2",
                "holder-holder-contract": "multiplexer-holder/2"
            },
            "result": { "safe-path": "finish the session and restart the holder" }
        });
        let why = refusal_text(&record).expect("the refusal is named");
        assert!(why.contains("multiplexer-holder/1"), "the client's: {:?}", why);
        assert!(why.contains("multiplexer-holder/2"), "the holder's: {:?}", why);
        assert!(why.contains("event-log-format/2"), "both events: {:?}", why);
        assert!(why.contains("restart the holder"), "what to do: {:?}", why);
    }

    #[test]
    fn a_record_that_is_not_a_refusal_is_not_taken_for_one() {
        let record = json!({ "kind": "info", "what": "the records were read" });
        assert!(refusal_text(&record).is_none(), "no refusal here");
    }

    #[test]
    fn a_rewind_asks_the_holder_for_that_pane_at_that_record() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind work 12");
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "rewind");
                assert_eq!(request["pane"], "work");
                assert_eq!(request["seq"], 12);
            }
            _ => panic!("the rewind is one request"),
        }
        assert!(screen.message.contains("record 12"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_rewind_of_a_number_that_is_not_a_record_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind work later");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("not a record number"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_rewind_of_a_pane_that_is_not_there_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind nowhere 3");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("no pane named nowhere"), "the line: {:?}", screen.message);
    }

    #[test]
    fn the_rewind_panel_shows_the_journal_and_leaves_the_live_pane_alone() {
        let mut screen = a_screen_with_words();
        let before = screen.panes[0].lines.clone();
        let record = json!({
            "kind": "info",
            "who": "holder",
            "what": "the pane was read back",
            "seq": 12,
            "outputs": { "pane": "work", "seq": 12, "count": 2,
                         "lines": ["line 1", "line 2"] }
        });
        screen.take_rewind(&record);
        let panel = screen.panel.as_ref().expect("the panel is there");
        assert!(panel.title.contains("record 12"), "the title: {:?}", panel.title);
        let shown = panel.lines.join("\n");
        assert!(shown.contains("line 1"), "the journal's own line: {:?}", shown);
        assert!(shown.contains("not changed"), "the live pane is named: {:?}", shown);
        assert_eq!(screen.panes[0].lines, before, "the live pane keeps its own lines");
    }

    #[test]
    fn a_paste_goes_to_the_focused_pane_in_one_request() {
        let mut screen = a_screen();
        let action = screen.paste_text("the words".to_string());
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "send");
                assert_eq!(request["pane"], "work");
                assert_eq!(request["data"], "the words");
            }
            _ => panic!("the paste is one request"),
        }
    }

    #[test]
    fn a_watching_screen_says_so_and_changes_nothing() {
        let mut screen = a_screen();
        screen.set_watch(true);
        let drawing = screen.draw();
        assert!(drawing.contains("WATCH/"), "the mode row says it watches: {:?}", drawing);
        let left = screen.watch_filter(Action::Quit);
        assert!(matches!(left, Some(Action::Quit)), "leaving is not a change");
        let taken = screen.watch_filter(Action::Send(b"rm -rf /".to_vec()));
        assert!(taken.is_none(), "a watcher's send is taken away");
        assert!(
            screen.message.contains("cannot change it"),
            "the message names the rule: {:?}",
            screen.message
        );
    }

    #[test]
    fn a_screen_that_is_not_watching_keeps_every_action() {
        let mut screen = a_screen();
        let sent = screen.watch_filter(Action::Send(b"echo hi".to_vec()));
        match sent {
            Some(Action::Send(bytes)) => assert_eq!(bytes, b"echo hi"),
            _ => panic!("the owner's own key is not taken away"),
        }
        assert!(screen.message.is_empty(), "no message is made up: {:?}", screen.message);
    }
