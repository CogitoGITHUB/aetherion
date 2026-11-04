    use super::*;

    /// state is a session with two tabs and two panes.
    fn state() -> State {
        State {
            tabs: 2,
            panes: 2,
        }
    }

    #[test]
    fn visual_starts_at_the_root_map() {
        let keymap = Keymap::empty();
        assert_eq!(keymap.explorer_map(), Context::Root);
        assert_eq!(keymap.group(), None);
    }

    #[test]
    fn the_i_enters_insert() {
        let mut keymap = Keymap::empty();
        assert_eq!(
            keymap.resolve(Mode::Visual, b'i'),
            Resolution::Command(Command::EnterInsert)
        );
    }

    #[test]
    fn space_opens_the_explorer_in_visual_mode() {
        let mut keymap = Keymap::empty();
        assert_eq!(
            keymap.resolve(Mode::Visual, b' '),
            Resolution::Command(Command::OpenExplorer)
        );
    }

    #[test]
    fn insert_mode_passes_the_keys_to_the_pane() {
        let mut keymap = Keymap::empty();
        assert_eq!(keymap.resolve(Mode::Insert, b'a'), Resolution::Pass);
        assert_eq!(keymap.resolve(Mode::Insert, b' '), Resolution::Pass);
        assert_eq!(keymap.resolve(Mode::Insert, 0x03), Resolution::Pass);
    }

    #[test]
    fn a_sequence_runs_the_command_of_its_last_key() {
        let mut keymap = Keymap::empty();
        assert_eq!(keymap.resolve(Mode::Visual, b'p'), Resolution::Pending);
        assert_eq!(keymap.group(), Some(Context::Panes));
        assert_eq!(
            keymap.resolve(Mode::Visual, b'a'),
            Resolution::Command(Command::PaneAdd)
        );
    }

    #[test]
    fn a_wrong_key_cancels_the_sequence_and_does_nothing() {
        let mut keymap = Keymap::empty();
        keymap.resolve(Mode::Visual, b'p');
        assert_eq!(keymap.resolve(Mode::Visual, b'z'), Resolution::Ignore);
        assert_eq!(keymap.pending_keys(), "");
        assert_eq!(keymap.group(), None);
    }

    #[test]
    fn the_escape_cancels_the_sequence() {
        let mut keymap = Keymap::empty();
        keymap.resolve(Mode::Visual, b'p');
        keymap.cancel();
        assert_eq!(keymap.pending_keys(), "");
        assert_eq!(keymap.resolve(Mode::Visual, b'a'), Resolution::Ignore);
    }

    #[test]
    fn the_explorer_shows_the_root_map_and_its_groups() {
        let mut keymap = Keymap::empty();
        assert_eq!(keymap.explorer_map(), Context::Root);
        assert_eq!(keymap.resolve(Mode::Explorer, b't'), Resolution::Map(Context::Tabs));
    }

    #[test]
    fn the_explorer_walks_into_a_group() {
        let mut keymap = Keymap::empty();
        assert_eq!(keymap.resolve(Mode::Explorer, b'p'), Resolution::Map(Context::Panes));
        keymap.open_map(Context::Panes);
        assert_eq!(keymap.explorer_map(), Context::Panes);
        assert_eq!(
            keymap.resolve(Mode::Explorer, b'o'),
            Resolution::Command(Command::OpenAgent)
        );
    }

    #[test]
    fn the_escape_leaves_the_explorer_one_level_up() {
        let mut keymap = Keymap::empty();
        keymap.open_map(Context::Panes);
        assert_eq!(keymap.resolve(Mode::Explorer, 0x1b), Resolution::Map(Context::Root));
        assert_eq!(keymap.explorer_map(), Context::Root);
        assert_eq!(
            keymap.resolve(Mode::Explorer, 0x1b),
            Resolution::Command(Command::CloseExplorer)
        );
    }

    #[test]
    fn no_binding_needs_a_modifier() {
        for context in [
            Context::Root,
            Context::Tabs,
            Context::Panes,
            Context::Commands,
            Context::Sessions,
        ] {
            for binding in bindings(context) {
                for byte in binding.bytes {
                    assert!(
                        *byte >= 0x20 || *byte == 0x1b,
                        "the binding {} holds a control key",
                        binding.keys
                    );
                }
            }
        }
    }

    #[test]
    fn every_binding_of_the_selection_is_reachable() {
        for binding in bindings(Context::Select) {
            let mut keymap = Keymap::empty();
            let last = *binding.bytes.last().unwrap();
            for byte in &binding.bytes[..binding.bytes.len() - 1] {
                keymap.resolve(Mode::Select, *byte);
            }
            let resolution = keymap.resolve(Mode::Select, last);
            assert_eq!(
                resolution,
                Resolution::Command(binding.action_as_command().unwrap()),
                "the binding {} does not run its command",
                binding.keys
            );
        }
    }

    #[test]
    fn every_binding_is_reachable_from_its_own_map() {
        for context in [
            Context::Root,
            Context::Tabs,
            Context::Panes,
            Context::Commands,
            Context::Sessions,
        ] {
            for binding in bindings(context) {
                let mut keymap = Keymap::empty();
                let last = *binding.bytes.last().unwrap();
                for byte in &binding.bytes[..binding.bytes.len() - 1] {
                    keymap.resolve(Mode::Visual, *byte);
                }
                let resolution = keymap.resolve(Mode::Visual, last);
                match binding.action_as_command() {
                    // A command binding runs the command it says.
                    Some(command) => assert_eq!(
                        resolution,
                        Resolution::Command(command),
                        "the binding {} does not run its command",
                        binding.keys
                    ),
                    // The selection is a mode and not a group: the key
                    // enters it, and the mode line says which mode stands.
                    None if binding.action == Action::Map(Context::Select) => {
                        assert_eq!(
                            resolution,
                            Resolution::Command(Command::EnterSelect),
                            "the binding {} does not enter the selection",
                            binding.keys
                        )
                    }
                    // A group binding opens the group and waits for the next
                    // key of that group.
                    None => assert_eq!(
                        resolution,
                        Resolution::Pending,
                        "the binding {} does not open its group",
                        binding.keys
                    ),
                }
            }
        }
    }

    #[test]
    fn a_binding_that_needs_another_tab_says_so() {
        let binding = TABS
            .iter()
            .find(|binding| binding.need == Need::AnotherTab)
            .expect("the tabs map has a binding that needs a second tab");
        let one = State {
            tabs: 1,
            panes: 1,
        };
        assert!(!binding.available(&one));
        assert!(binding.available(&state()));
    }

    #[test]
    fn the_explorer_shows_the_same_bindings_the_keys_use() {
        // The explorer and the keys read one table: the explorer shows the
        // root map, and the root map is what Visual mode reads.
        let keymap = Keymap::empty();
        for binding in ROOT {
            if binding.is_map() {
                continue;
            }
            let last = *binding.bytes.last().unwrap();
            let mut keys = Keymap::empty();
            for byte in &binding.bytes[..binding.bytes.len() - 1] {
                keys.resolve(Mode::Visual, *byte);
            }
            assert_eq!(
                keys.resolve(Mode::Visual, last),
                Resolution::Command(binding.action_as_command().unwrap()),
                "the binding {} does not do what the explorer shows",
                binding.keys
            );
        }
        let _ = keymap.explorer_map();
    }
