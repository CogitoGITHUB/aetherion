use super::*;

/// SELECT is the map of the selection. The keys move a point over the
/// visible text of the focused pane, one key sets the mark, and the
/// region is the text between the mark and the point.
///
/// The escape leaves the selection and does nothing else: no text is
/// copied, no bundle is sent and no pane opens. The escape is not a
/// binding here: the byte stream is what tells a lone escape from the
/// escape that begins an arrow key, and the program reads the escape
/// where the byte stream hands it over.
pub static SELECT: &[Binding] = &[
    Binding {
        keys: "Left",
        bytes: b"\x1b[D",
        about: "the point one character to the left",
        action: Action::Command(Command::SelectLeft),
        need: Need::Always,
    },
    Binding {
        keys: "Right",
        bytes: b"\x1b[C",
        about: "the point one character to the right",
        action: Action::Command(Command::SelectRight),
        need: Need::Always,
    },
    Binding {
        keys: "Up",
        bytes: b"\x1b[A",
        about: "the point one line up",
        action: Action::Command(Command::SelectUp),
        need: Need::Always,
    },
    Binding {
        keys: "Down",
        bytes: b"\x1b[B",
        about: "the point one line down",
        action: Action::Command(Command::SelectDown),
        need: Need::Always,
    },
    Binding {
        keys: "w b",
        bytes: b"wb",
        about: "the point to the start of the word before it",
        action: Action::Command(Command::SelectWordLeft),
        need: Need::Always,
    },
    Binding {
        keys: "w f",
        bytes: b"wf",
        about: "the point to the start of the next word",
        action: Action::Command(Command::SelectWordRight),
        need: Need::Always,
    },
    Binding {
        keys: "m",
        bytes: b"m",
        about: "the mark: the anchor of the region",
        action: Action::Command(Command::SelectMark),
        need: Need::Always,
    },
    Binding {
        keys: "M",
        bytes: b"M",
        about: "pop the newest mark; the anchor below it stands",
        action: Action::Command(Command::SelectPopMark),
        need: Need::Always,
    },
    Binding {
        keys: "y",
        bytes: b"y",
        about: "copy the region into the multiplexer's own ring",
        action: Action::Command(Command::SelectCopy),
        need: Need::Always,
    },
    Binding {
        keys: "Y",
        bytes: b"Y",
        about: "copy the line the point stands on",
        action: Action::Command(Command::SelectCopyLine),
        need: Need::Always,
    },
    Binding {
        keys: "o",
        bytes: b"o",
        about: "copy the region out to the Android clipboard",
        action: Action::Command(Command::SelectCopyOut),
        need: Need::Always,
    },
    Binding {
        keys: "P",
        bytes: b"P",
        about: "paste the Android clipboard into the focused pane",
        action: Action::Command(Command::PasteClipboard),
        need: Need::Always,
    },
    Binding {
        keys: "s",
        bytes: b"s",
        about: "send the region to the agent, in the bundle",
        action: Action::Command(Command::SelectSend),
        need: Need::Always,
    },
    Binding {
        keys: "p o",
        bytes: b"po",
        about: "open the agent beside this pane, with the region",
        action: Action::Command(Command::SelectAgentHere),
        need: Need::Always,
    },
    Binding {
        keys: "PageUp",
        bytes: b"\x1b[5~",
        about: "the view one page up; the pick starts again over the fresh text",
        action: Action::Command(Command::PageUp),
        need: Need::Always,
    },
    Binding {
        keys: "PageDown",
        bytes: b"\x1b[6~",
        about: "the view one page down; the pick starts again over the fresh text",
        action: Action::Command(Command::PageDown),
        need: Need::Always,
    },
];
