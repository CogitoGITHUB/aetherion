use super::*;

/// Command is what the multiplexer does. The dispatch does not know which key
/// asked for it, so a command can be run from a key, from the explorer, or
/// from the command line, and it does the same thing each time.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[allow(dead_code)]
pub enum Command {
    Nothing,
    /// EnterInsert puts the keyboard into the focused pane.
    EnterInsert,
    /// OpenCommandLine opens the line where the owner writes a command.
    OpenCommandLine,
    /// OpenExplorer opens the keymap explorer.
    OpenExplorer,
    /// CloseExplorer closes the keymap explorer and gives the keyboard back.
    CloseExplorer,
    /// Detach leaves the multiplexer; the session goes on without it.
    Detach,
    TabAdd,
    TabClose,
    TabRename,
    TabNext,
    TabPrevious,
    PaneAdd,
    PaneClose,
    PaneRename,
    PaneNext,
    PanePrevious,
    /// PaneGrow gives the focused pane more of the space.
    PaneGrow,
    /// PaneShrink gives the focused pane less of the space.
    PaneShrink,
    /// OpenAgent opens the agent beside the focused pane, with the pane's
    /// context attached.
    OpenAgent,
    /// OpenEditor opens the editor beside the focused pane.
    OpenEditor,
    /// ShowRecords opens the panel with the session's records.
    ShowRecords,
    /// ShowSessions opens the panel with the sessions.
    ShowSessions,
    /// GitOverview shows the repository, its worktrees and its distance.
    GitOverview,
    /// GitChanged shows the changed files.
    GitChanged,
    /// GitDiff shows the diff of the working tree against the index.
    GitDiff,
    /// GitHistory shows the commits.
    GitHistory,
    /// GitBranches shows the branches and their distance.
    GitBranches,
    /// GitWorktrees shows every worktree of the repository.
    GitWorktrees,
    /// LevelHide hides one level of the screen's own rows.
    LevelHide,
    /// LevelShow shows one level more of the screen's own rows.
    LevelShow,
    /// PageUp scrolls the focused pane's view one page up: the older words.
    PageUp,
    /// PageDown scrolls the focused pane's view one page down: the newer
    /// words.
    PageDown,
    /// WorkspaceList shows the workspaces and their projects.
    WorkspaceList,
    /// WorkspaceContext shows the project context as it stands.
    WorkspaceContext,
    /// WorkspaceOpen asks for the name of the project to open.
    WorkspaceOpen,
    /// AskEditor asks the editor what it owns, through the editor's own
    /// server.
    AskEditor,
    /// EnterSelect opens the selection on the focused pane.
    EnterSelect,
    /// SelectLeft moves the point one character to the left.
    SelectLeft,
    /// SelectRight moves the point one character to the right.
    SelectRight,
    /// SelectUp moves the point one line up.
    SelectUp,
    /// SelectDown moves the point one line down.
    SelectDown,
    /// SelectWordLeft moves the point to the start of the word before it.
    SelectWordLeft,
    /// SelectWordRight moves the point to the start of the next word.
    SelectWordRight,
    /// SelectMark pushes the mark where the point stands.
    SelectMark,
    /// SelectPopMark takes the newest mark off the ring.
    SelectPopMark,
    /// SelectCopy copies the region into the multiplexer's own ring.
    SelectCopy,
    /// SelectCopyLine copies the line the point stands on.
    SelectCopyLine,
    /// SelectCopyOut copies the region out to the Android clipboard.
    SelectCopyOut,
    /// SelectSend sends the region to the agent in the bundle.
    SelectSend,
    /// SelectAgentHere opens the agent beside the pane, with the region.
    SelectAgentHere,
    /// PasteClipboard pastes the Android clipboard into the focused pane.
    PasteClipboard,
    /// LeaveSelect leaves the selection and does nothing else.
    LeaveSelect,
}

