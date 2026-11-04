use super::*;

pub static GIT: &[Binding] = &[
    Binding {
        keys: "g o",
        bytes: b"go",
        about: "the repository: the branch, the distance, the worktrees",
        action: Action::Command(Command::GitOverview),
        need: Need::Always,
    },
    Binding {
        keys: "g c",
        bytes: b"gc",
        about: "the changed files: staged, unstaged, untracked, conflicts",
        action: Action::Command(Command::GitChanged),
        need: Need::Always,
    },
    Binding {
        keys: "g d",
        bytes: b"gd",
        about: "the diff: the working tree against the index",
        action: Action::Command(Command::GitDiff),
        need: Need::Always,
    },
    Binding {
        keys: "g h",
        bytes: b"gh",
        about: "the history: the commits, newest first",
        action: Action::Command(Command::GitHistory),
        need: Need::Always,
    },
    Binding {
        keys: "g b",
        bytes: b"gb",
        about: "the branches, and how far they are from their upstream",
        action: Action::Command(Command::GitBranches),
        need: Need::Always,
    },
    Binding {
        keys: "g w",
        bytes: b"gw",
        about: "the worktrees: every one of them, and the changes it holds",
        action: Action::Command(Command::GitWorktrees),
        need: Need::Always,
    },
];
