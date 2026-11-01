
## Planned work saved from the old docs (2026-11-01)

The old docs are deleted. These are their plans that todo.aiu holds only as one line. Owner questions of 13.9 are open. Question 15.8.3 is in todo.aiu, 15.8.1 and 15.8.2 are obsolete.

## 12. Future plans

Ask the owner before starting any of these.

- Tab completion for .aiu: one completion core, in a module loaded on first use (never required by quick.rkt, cli.rkt, lean.rkt, live.rkt or home.rkt). Input is the page text and the point; output is candidates by context: block names at a line start (with a snippet for the start line, the end line and the point between), values after kind:, language: and todo:, tags already used across pages after tags:. Read block names and declarations from the notation engine; do not copy them. If it has no list to read, keep a small table in the editor and make the gate compare it with the notation.
- Completion key: tab is the trigger of the write layer, so use tab tab and leave the layer with escape.
- LSP: a separate stdio server over the same core, answering textDocument/completion, built after the in-editor version.

## 13. Plan: marks and bookmarks

Status: planned, nothing built. Ask the owner before starting. Modelled on Neovim marks and the jumplist and on Emacs bookmarks, registers and the mark ring, but anchored to BLOCKS, because pages are boxes and blocks move (m, h, t).

### 13.1 What exists in the two editors (reference)

| Idea | Neovim | Emacs |
|---|---|---|
| local mark in one buffer | m a to z, jump with a quote or a backtick | register: C-x r SPC, jump C-x r j |
| global mark that opens its file | m A to Z | bookmark: C-x r m, jump C-x r b |
| list and delete | :marks, :delmarks | C-x r l (bookmark list), delete in that list |
| survives a restart | shada file | bookmark file, saved on exit or at once |
| automatic marks | last change, last insert, last jump, selection start and end | the mark ring: set mark, C-x C-x swaps, C-u C-SPC pops |
| history of places | jumplist C-o and C-i, changelist g; and g, | global mark ring |

### 13.2 What AIU EDITOR does

Four things, in this order of build:

1. Local marks: a to z, kept per file.
2. Global marks and named bookmarks: A to Z and free names, kept for every file, opening the file when used.
3. Jumplist: every jump (find, tab switch, mark jump, next-block, block-end) pushes the place; back and forward walk it.
4. Automatic marks: last change, last edit block, last jump, last visual block.

### 13.3 Anchor: a place is a block, not a line

A place is stored as: file path, block name, depth, the number of the block among its siblings, the first text line of the block (up to 60 characters), and the byte offset inside the block.

To jump: parse the page (one cached `page-of`), try in order: same sibling number and same name and same first line; same name and same first line anywhere in the file; same sibling number and name; the stored byte offset clamped to the file. The jump lights the block and puts the point at the stored offset inside it. A plain text file uses the byte offset only.

A block moved with m keeps its marks because the first-line match finds it. An edited first line falls back to the number, then to the offset. A mark that finds nothing says so in a notification and keeps the mark.

### 13.4 Keys (all in the visual layer, none collide with w i h t n s m a p e c k l x o d)

| Keys | Command | Does |
|---|---|---|
| space m, then a to z | mark-set | local mark at the lit block |
| space m, then A to Z | mark-set-global | global mark, opens its file |
| space j, then a to z or A to Z | mark-jump | jump to that mark |
| space j, then space j | mark-jump-last | back to where the last jump started |
| space m, then m | mark-list | list all marks and bookmarks in fzf (reuses `run-picker` of `finder.rkt`), a pick jumps |
| space m, then x, then a letter | mark-delete | delete one mark |
| space [ and space ] | jump-back and jump-forward | walk the jumplist |
| space m, then n | bookmark-set | ask a name in the mode line, store a named bookmark |
| space j, then b | bookmark-jump | fzf over the named bookmarks |

The popup (`menu-groups` in `live.rkt`) gets a marks group so the keys show after space m and space j. A key needs a row there, a row in `normal-keys` and a command in the table, or the gate (`key-check`, `explorer-check`) goes red.

The letter after space m or space j is read as the next key in a waiting sequence. The sequences are generated from a to z and A to Z in `keymaps.rkt` by a loop, not typed by hand, so the table stays small to read.

### 13.5 Storage

- File: `~/.aiu-marks.rktd`, outside the project tree (the rule: no state inside the tree). One s-expression: local marks by file, global marks, named bookmarks, the jumplist (last 100), the automatic marks.
- Written at once after each change, in a thread, by writing a temp file in the same folder and renaming it, so a crash never leaves half a file.
- Read in a thread after the first paint (`paint-ready`), never before. A mark key pressed before the read ends waits for it, with no message.
- Local marks are keyed by the complete path of the file. A renamed file loses its marks; the list shows the missing ones in a dim line and deletes them on request.

### 13.6 Where it shows

- Strip: the git strip column stays for git. Marks show as the letter at the RIGHT edge of the first drawn line of the block, outside the box, so nothing inside the drawing changes. One column, taken only when the file has marks.
- Mode line and bar: the layer cell shows the count, for example `visual general [any] m3`.
- Dashboard: a section with the named bookmarks, one per line, with the key to open them (number keys stay for pages).
- Tabs: no change.

### 13.7 Build plan (one script and one gate run per step, owner tries each by hand)

| Step | Work | Done when |
|---|---|---|
| 1 | `dashboard/marks.rkt`: the data (racket/base only), `place-of` (block to place), `find-place` (place to block, the fallback order of 13.3), the file read and write | a script proof in the gate: set a place, move the block, find it again |
| 2 | commands `mark-set`, `mark-jump`, `mark-delete`, keys by loop in `keymaps.rkt`, menu rows, notifications | space m a then space j a works by hand |
| 3 | jumplist: push on every jump, `jump-back`, `jump-forward`, last-jump mark | back and forward work across tabs |
| 4 | global marks and named bookmarks, the fzf list `mark-list` and `bookmark-jump` | a bookmark opens its file in a tab at its block |
| 5 | strip letters, bar count, dashboard section | visible and no slower |
| 6 | automatic marks: last change (set by `edit-hook`), last edit block, last visual block | space j then a special letter jumps |
| 7 | test page section and README tables updated | `test.aiu` teaches the keys |

### 13.8 Rules for the build

- Lazy: `marks.rkt` is loaded on the first mark key, the way the send stub loads, and never required by `quick.rkt`, `cli.rkt`, `lean.rkt`, `live.rkt` or `home.rkt`. Use `dynamic-require` in a stub command.
- No hot path request is added to a keypress; a jump asks `page-of` once (cached).
- After each step: gate green, then the owner holds h or t and says if it is smooth. Measure a keypress, not only the start.
- No change to AIU NOTATION. If block identity needs an id in the notation, ask the owner first. The plan above works without one.

### 13.9 Open questions for the owner

1. Are the keys in 13.4 right, or should marks live in their own layer like the bar does?
2. Should local marks use the block or the exact character position when both are known?
3. Should the marks letter show at the right edge of the page, or only in the list?

## 14. Plan: undo tree and undo with git

Status: step 1 built (history kept), the rest planned. Ask the owner before each step.

### 14.1 Why the history file

`current_text` replays the journal on top of the saved file, so the journal must be cleared on save or every edit would apply twice. Autosave saves after each edit, so the journal is empty almost always. `journal::archive` (`journal/journal.rs`), called by `OP_SAVE` in `join/hot-path.rs` before the clear, keeps `<journal>.base` (the file text before the first save) and appends every record to `<journal>.history`. State n is `replay(base, history[0..n])`. Older edits made before this change have no history.

### 14.2 Undo tree

Every record becomes a node: id, parent id, time. Undo moves to the parent, and a new edit after an undo makes a branch, so no redo path is lost. A tree view (keys h and t between nodes, a diff of the node) shows the branches. The tree file lives beside the history. Restoring a node writes the replayed text through the normal edit ops so it is itself undoable. Needs one new hot path op that answers the text at node n.

### 14.3 Undo with git

Revert a hunk or a block with git apply -R using the hunks of the git strip (`gutter.rkt`), and restore a block or the file from any commit of its log. Built after the tree.

### 14.4 Keys

Proposed: u undo, r redo (plain keys in visual are free), space u the tree view (space u is level-up today, ask first). Each key needs a row in `normal-keys`, a command and a `menu-groups` row.

### 14.5 Build steps

| Step | Work | State |
|---|---|---|
| 1 | history file and base kept on save | built, rebuild the hot path |
| 2 | op that answers the text at node n, undo and redo keys with a linear history | planned |
| 3 | tree with parents and branches, tree view | planned |
| 4 | git hunk and block revert, restore from commit | planned |

### 14.6 Other missing features

Search and replace with n and N, block cut copy paste, folding, split view, repeat and macros, outline list, git stage and blame, reload when the file changes on disk, spell check.


### Open owner questions 13.9

1. Are the keys in 13.4 right, or should marks live in their own layer like the bar does?
2. Should local marks use the block or the exact character position when both are known?
3. Should the marks letter show at the right edge of the page, or only in the list?
