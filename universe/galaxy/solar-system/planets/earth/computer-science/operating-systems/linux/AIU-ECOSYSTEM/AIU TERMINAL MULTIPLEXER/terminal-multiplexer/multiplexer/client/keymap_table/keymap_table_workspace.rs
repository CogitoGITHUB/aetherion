use super::*;

pub static WORKSPACE: &[Binding] = &[
    Binding {
        keys: "w w",
        bytes: b"ww",
        about: "the workspaces and their projects",
        action: Action::Command(Command::WorkspaceList),
        need: Need::Always,
    },
    Binding {
        keys: "w p",
        bytes: b"wp",
        about: "the project context as it stands",
        action: Action::Command(Command::WorkspaceContext),
        need: Need::Always,
    },
    Binding {
        keys: "w o",
        bytes: b"wo",
        about: "open the project context: the name of the project follows",
        action: Action::Command(Command::WorkspaceOpen),
        need: Need::Always,
    },
    Binding {
        keys: "w e",
        bytes: b"we",
        about: "ask the editor what it owns, through the editor's own server",
        action: Action::Command(Command::AskEditor),
        need: Need::Always,
    },
];
