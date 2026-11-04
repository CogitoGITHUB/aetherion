use super::*;

/// SESSIONS is the map of the session commands.
pub static SESSIONS: &[Binding] = &[
    Binding {
        keys: "s d",
        bytes: b"sd",
        about: "detach: leave the multiplexer, the session goes on",
        action: Action::Command(Command::Detach),
        need: Need::Always,
    },
    Binding {
        keys: "s l",
        bytes: b"sl",
        about: "the sessions this multiplexer knows",
        action: Action::Command(Command::ShowSessions),
        need: Need::Always,
    },
];
