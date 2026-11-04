use super::*;

/// PANES is the map of the pane commands.
pub static PANES: &[Binding] = &[
    Binding {
        keys: "p a",
        bytes: b"pa",
        about: "a new pane",
        action: Action::Command(Command::PaneAdd),
        need: Need::Always,
    },
    Binding {
        keys: "p c",
        bytes: b"pc",
        about: "close this pane",
        action: Action::Command(Command::PaneClose),
        need: Need::Always,
    },
    Binding {
        keys: "p r",
        bytes: b"pr",
        about: "rename this pane",
        action: Action::Command(Command::PaneRename),
        need: Need::Always,
    },
    Binding {
        keys: "p n",
        bytes: b"pn",
        about: "the next pane",
        action: Action::Command(Command::PaneNext),
        need: Need::AnotherPane,
    },
    Binding {
        keys: "p p",
        bytes: b"pp",
        about: "the pane before",
        action: Action::Command(Command::PanePrevious),
        need: Need::AnotherPane,
    },
    Binding {
        keys: "p o",
        bytes: b"po",
        about: "open the agent beside this pane, with its context",
        action: Action::Command(Command::OpenAgent),
        need: Need::Always,
    },
    Binding {
        keys: "p e",
        bytes: b"pe",
        about: "open the editor beside this pane",
        action: Action::Command(Command::OpenEditor),
        need: Need::Always,
    },
    Binding {
        keys: "p +",
        bytes: b"p+",
        about: "this pane takes more of the space",
        action: Action::Command(Command::PaneGrow),
        need: Need::Always,
    },
    Binding {
        keys: "p -",
        bytes: b"p-",
        about: "this pane takes less of the space",
        action: Action::Command(Command::PaneShrink),
        need: Need::Always,
    },
];
