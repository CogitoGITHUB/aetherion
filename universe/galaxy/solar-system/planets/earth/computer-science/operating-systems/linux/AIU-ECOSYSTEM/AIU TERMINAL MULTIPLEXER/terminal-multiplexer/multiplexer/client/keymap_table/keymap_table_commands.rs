use super::*;

pub static COMMANDS: &[Binding] = &[
    Binding {
        keys: "c l",
        bytes: b"cl",
        about: "the records of this session",
        action: Action::Command(Command::ShowRecords),
        need: Need::Always,
    },
    Binding {
        keys: "c :",
        bytes: b"c:",
        about: "the command line",
        action: Action::Command(Command::OpenCommandLine),
        need: Need::Always,
    },
];
