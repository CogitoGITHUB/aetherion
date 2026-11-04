use super::*;

pub static TABS: &[Binding] = &[
    Binding {
        keys: "t a",
        bytes: b"ta",
        about: "a new tab, with a pane in it",
        action: Action::Command(Command::TabAdd),
        need: Need::Always,
    },
    Binding {
        keys: "t c",
        bytes: b"tc",
        about: "close this tab",
        action: Action::Command(Command::TabClose),
        need: Need::Always,
    },
    Binding {
        keys: "t r",
        bytes: b"tr",
        about: "rename this tab",
        action: Action::Command(Command::TabRename),
        need: Need::Always,
    },
    Binding {
        keys: "t n",
        bytes: b"tn",
        about: "the next tab",
        action: Action::Command(Command::TabNext),
        need: Need::AnotherTab,
    },
    Binding {
        keys: "t p",
        bytes: b"tp",
        about: "the tab before",
        action: Action::Command(Command::TabPrevious),
        need: Need::AnotherTab,
    },
];
