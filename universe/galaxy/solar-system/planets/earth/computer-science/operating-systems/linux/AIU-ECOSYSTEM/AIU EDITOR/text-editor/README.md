# AIU EDITOR

AI agents: README-AI.md section 0 (START HERE) says what to do next.

A terminal text editor written in Racket with a Rust hot path. It is built so a
file is on the screen in under a second, and everything else loads behind it.

AI agents: read README-AI.md first, not this file.

## 1. Lazy loading: the main feature

The rule is open first, load later. The file is drawn before anything else is
loaded, you can type at once, and the rest of the editor arrives while you work.

| Moment | What happens | Measured on the phone |
|---|---|---|
| first paint | the first lines of the file are drawn, drawn as boxes, with no loading text | 0.8 s (was 2.1 s) |
| while loading | keys you type wait in the terminal and run when the editor is ready; none are lost | a quit typed at once quits |
| ready | the commands, the keys and the real screen | about 2 s |
| first use | the send, audit and checkpoint code loads the first time you press the send key | on demand |
| after the paint | the home screen scans pages, todos and git in a thread and repaints by itself | about 8 s, in the background |
| never at start | the home screen does not start the hot path until you open a page | not started |

Why it is built this way: the phone has 2 cores, and every library loaded at
start costs time before the first paint. `json`, `racket/port` and `net/url`
were the slowest to load. So the first screen comes from a module that needs only
`racket/base`, and everything else is loaded after it or on first use.

## 2. Quick start

~~~
aiutd FILE      open a file
aiutd           open the home screen (no file is opened or created)
~~~

`aiutd` is a small sh script. It sets `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`,
`PLTCOMPILEDROOTS` and `AIU_ROOT`, then starts the editor.

## 3. Shell compatibility

| Shell | How it works |
|---|---|
| bash, sh, zsh | `aiutd` is plain POSIX sh with no bashisms; call it directly |
| nushell | call `aiutd FILE` directly; run bash snippets as `bash -c "..."` |
| scripts and snippets | written for bash; no `&&` is needed in nushell because the whole snippet runs inside `bash -c` |

The gate runs under nushell: `nu gate/check.nu`.

## 4. Requirements

| Tool | Needed | Note |
|---|---|---|
| Racket full | yes | `/root/home/shape/opt/racket-full/bin/racket` |
| Rust hot path binary | yes for files | default `/tmp/editor-target/debug/hot-path`, or `AIU_HOT_PATH_BIN` |
| AIU NOTATION binary | no | draws the home screen and pages as boxes; without it the page text shows as it is |
| git | no | feeds the git rows of the home screen |
| fzf and rg | for find | space / needs both |
| nushell | for the gate | `nu gate/check.nu` |

## 5. Keys

The trigger is space, and tab in the write layer. Nothing needs a modifier key. SPC is the space key. Every key below is read from `editor/src/routes/keymaps.rkt`.

Visual layer (the page is read):

| Key | Does |
|---|---|
| h | on a page: light the block before |
| t | on a page: light the block after |
| n | move the point left |
| s | move the point right |
| w | on a page: write the lit block as raw text, markers shown (see Block editing) |
| i | on a page: edit only the text of the lit block, inside its drawn box |
| m | the move layer |
| backspace | take back the character before the point |
| escape | stay in the visual layer |
| space f | the write layer on the whole page, raw |
| space v | the select layer |
| space s | save |
| space q | quit |
| space u | show one level more of the rows of the editor (0 to 3) |
| space ? | the explorer |
| space g | send (loads its code on first use) |
| space b | the bar layer (see Bar) |
| space t | the tab layer (see Tabs) |
| space / | find with fzf (see Find) |
| space z | focus mode: hide the bar, the tabs and the one line, and again to bring them back |
| space k | check (pages) |
| space h | open the dashboard (home screen) |
| a p e c k l x o d | pick what h and t move between (see Pick) |
| space n, e | next block, block end |
| 1 to 9 | on the home screen, open that page |
| space, then wait | pops up a floating menu in the middle of the screen with the page hidden behind it: the modes you can switch to as a table with the key of each, and below it the keys of the active layer in boxes by group |

Write layer (keys are text, tab is the trigger):

| Key | Does |
|---|---|
| tab tab | back to the visual layer |
| tab s | save |
| tab b | blocks |
| escape | save, then back to the visual layer |
| up, down, left, right | move the point |
| backspace | take back the character before the point |

Select layer (reached with space v):

| Key | Does |
|---|---|
| space space | the write layer |
| space v, escape | the visual layer |

Move layer (reached with m):

| Key | Does |
|---|---|
| h, t | swap the lit block with the one before or after it |
| escape | back to the visual layer |
## 6. Home screen

`aiutd` with no file opens the home screen. It is an AIU page built in memory by
`editor/src/dashboard/home.rkt` and drawn by the notation view, so it looks like
every other page: a title of kind dashboard, a paragraph of keys and scan age,
a paragraph of pages, a paragraph of work and git, and a comment that holds one
paragraph for each open todo the scan found. Every line is scanned from the
folder named by `AIU_ROOT`.

It shows the last scan at once, kept in `~/.aiu-home-scan.rktd` outside the
project tree, then scans in a thread and paints the result when it lands.
Untracked files are not counted in the git rows, because walking them is slow.
Commands that need a file do nothing on this screen.

## Block editing

On an .aiu page in the visual layer the block under the cursor is lit. Up and
down move the cursor from block to block. Two keys edit the lit block:

- w writes the block as raw text, with its start and end lines. Every other block stays drawn, and the raw lines sit behind the left edge of the box that holds the block, cut at a space to the width of the box and padded, and the right edges of the boxes are drawn on every line, so the boxes stay closed.
- i edits only the text of the block. The block stays drawn in its own box, its start and end lines stay hidden, and only the text lines inside the box turn raw. A line longer than the box is cut at a space, and the left edge of the box is drawn on every part and the right edge closes every line, so the box stays clean.

In both, typing stays inside the block (for i, inside its text) and the
backspace stops at its start. Escape draws the page again. A block that holds
other blocks, such as a section, has no text of its own: i then does the same
as w. A block whose lines cannot be told from the drawing is lit as its parent
block, and when no block can be told the key w opens the whole page to write.
Space f writes the whole page raw. Space space is bound only in the select layer, and space w is not a key.
A plain text file still scrolls with h and t.

## Pick

In the visual layer plain keys pick what h and t move between: a any block, p paragraph, e section, c code, k comment, l title, x any todo, o open todo, d done todo. h and t never change. The mode line shows the sub-mode and the pick: visual general (pick any), visual navigation (any other pick), visual selection (the select layer), for example visual navigation [todo open]. The bar, its side strip and the one line show it. A todo is a paragraph with a todo: line; its state is the first word after todo: (done or open), no word is open.

## Notifications

Code: `editor/src/dashboard/notify.rkt` (racket/base and box.rkt only). `notify!` takes a level (info, warn, error) and a text; the box stays 2, 3 or 5 seconds, an identical text replaces the old one, at most 3 show. `notify-overlay` is added to the overlay of the paint in `repaint-now` (`live.rkt`), below a top bar or tabs, and a thread repaints through `notify-repaint` when one expires. An unbound key says no key and the keys of the sequence, with the sub-mode. Errors are drawn red.

## Paint without flicker

`paint` in `screen.rkt` no longer clears the screen. It homes the cursor, puts an erase of the line before every row (`erase-lines`) and wraps the frame in the synchronized update codes `sync-begin` and `sync-end` (`?2026h`, `?2026l`), which a terminal that does not know them ignores. The bar, the tabs and the page are overwritten in place, so nothing blanks between keys. `quick.rkt` still clears once for the first paint.

## Popup pick box

In the visual layer the SPC popup has a box named pick with the keys a p e c k l x o d, built from `normal-keys` (the commands that start with kind-). The title of the popup shows the sub-mode, for example visual general [any].

## State after the session of 2026-10-31

- Gate green, 17 stages. Kind layer removed: the picks are plain keys in visual (a p e c k l x o d), sub-modes visual general, visual navigation, visual selection, shown in the bar, the side strip, the one line and the SPC popup (a pick box and the sub-mode in the title).
- Notifications: `dashboard/notify.rkt`, an unbound key shows a warn box top right instead of printing over the page.
- Paint no longer sends the clear code: it homes the cursor, erases each line and wraps the frame in ?2026h and ?2026l (`screen.rkt`). Only `quick.rkt` clears, once. The timing loop that waits for the clear code still sees the first paint only.
- `quick.rkt` draws an .aiu page as boxes through the notation binary (`boxed-lines`, subprocess only, raw text when it fails) and says nothing about loading. Keys typed meanwhile queue and run when the editor is ready.
- machine/small.rkt exists but nothing requires it. The start path uses racket/path and racket/port. The swap felt slow on the phone, so measure a keypress before trying it again.
- Open: the owner reported flicker and slow movement after the quick-screen and small.rkt changes. Test by hand after any paint or start change. If it returns, revert the flicker patch in screen.rkt next.
- Open: still about 1.3 s from first paint to ready (json in protocol.rkt is needed for the first hot path message, so lazy json gains nothing; racket/path costs about 0.7 s, racket/port 0.4 s on this phone).

## Hot path answer cache

`ask-hot` in `join/hot-path.rkt` keeps the answers of the read requests notation, show, notation-render and notation-view, and clears all of them before and after any other request. A repaint asked the hot path 3 or more times per key (about 1.35 s a key on the phone); now it asks once. A new read-only operation may be added to `read-ops`; a new operation that changes text needs nothing.

## Git strip

`dashboard/gutter.rkt` keeps the hunks of `git diff -U0` for the open file, asked in a thread (4 s after the first ask, then every 15 s or when the file changes). `dashboard/gutterview.rkt` puts one column at the left of every drawn line of an .aiu page: plus for added, equals for changed, minus for removed, on the lines of each leaf block that a hunk touches (`bv-ranges`, exported by `blockview.rkt`, maps blocks to drawn lines). `repaint-now` in `live.rkt` takes one column off the page width for it. Lines are matched by the saved file, so unsaved edits can shift a mark until the next refresh. A removal between two blocks puts a minus on the first drawn line of the block after the gap (git reports it at the line before the gap), a removal inside a block marks the block equals. A swap of two blocks shows as plus on one block and minus at the gap, because git describes it that way. Only glyphs, no colour.

## Autosave

Every hot path request that changes text (type, delete, delete-at, insert-at) is followed by a save of the same file (`ask-hot`, `join/hot-path.rkt`, `edit-ops`, `save-after`), so git sees the change. `edit-hook` then marks the git row (`git-stale!`, bar.rkt) and the git strip (`gutter-stale!`, gutter.rkt) old, and the next paint asks git again. The 4 s wait applies only to the first git ask. The journal is cleared on every save; the history is kept in the history file (section 14).

## Git row and git in the tabs

`git-facts` (`bar.rkt`) answers branch, changed files, ahead, behind, last commit, then staged files, unstaged files, inserted lines and deleted lines (`git diff --shortstat HEAD`). `git-text` shows them in the git row of the bar. The git thread also sets `tab-git-text` (`tabs.rkt`), and `tab-rows` ends every tab bar, at all three levels, with a git section holding that text. Both are filled 4 s after start. Untracked files are still not counted.

## Git starts after the page is shown

No timer. `paint-ready` (`box.rkt`) is set by `live-session` right after the first full paint; `git-refresh-maybe` (bar.rkt) and `gutter-refresh-maybe` (gutter.rkt) do nothing until it is true, and one more repaint is started in a thread so they begin at once. Rule from the owner: once the page is shown and can be worked on, everything else may run in the background. Any older text in this file about waiting 4 s is obsolete.

## Dashboard key

Space h in the visual layer runs `home-open` (`commands.rkt`): it sets `home-request` and returns false, which ends the round of `live-session`; `file-session` (`lean.rkt`) then opens the home screen with `home-session` in the same terminal. A page picked there opens as a normal session. The popup lists it as dashboard in the view group.

## Dashboard page

`home-text` (`home.rkt`) builds the home page: title, a code block with the real keys (1 to 9, space ?, space /, space q), a code block with one page per line (`page-rows d 9`), the work paragraph and the open todos. The old text about space r (scan again) is gone because that key was deleted.

## Bar

Space b opens the bar layer, and the popup lists its keys. The bar has five parts: the layer, the time, git, the date and the keys. It stands at the bottom or the top as a box, or on the sides as strips with the letters upright: docked beside the page, or floating over it. With both sides the layer, git and the keys are on the left, and the time and the date on the right. A screen under 14 rows and the home screen keep the one old line. The time is read at each paint, and git is asked in a thread every 20 seconds, never in a paint.

| Key | Does |
|---|---|
| p | next place: bottom, top, left, right, sides |
| b, u, l, r, s | place: bottom, top, left, right, sides |
| d | docked or floating |
| x | hide the bar, or show it again |
| v | the level adjuster |
| escape | back to the visual layer |

Level adjuster (v): h hides one part, t shows one more. The parts come in the order layer, time, git, date, keys. Escape goes back to the bar layer.

## Tabs

Space t opens the tab layer, and the popup lists its keys. Every file you open stays as a tab, and the active one has a dot. The tab bar is one box with up to three sections, the level: 1 tabs, 2 project and tabs, 3 workspace, project and tabs. The workspace is the folder named AIU-ECOSYSTEM (or AIU_ROOT) and the folders beside it, the project is the first folder under it that holds the page, and the dot marks where the active page is. The project and workspace rows only show where the page is; they do not switch yet. The tab bar needs 16 rows and stays at the top or the bottom, never on the sides. It can share its edge with the bar when both stand at the same edge (j), or stand apart. Work not saved yet stays in the journal of its own file when you change tab.

| Key | Does |
|---|---|
| h | the tab before |
| t | the tab after |
| o | open the next page of the folder of the active tab, as a new tab |
| c | close the active tab (the last one stays) |
| p | the other place: top or bottom |
| u, b | place: top, bottom |
| j | share the edge with the bar, or stand apart |
| x | hide the tab bar, or show it again |
| v | the level adjuster |
| escape | back to the visual layer |

Level adjuster (v): h hides one level, t shows one more, escape goes back to the tab layer. Both bars open with every level shown: the tab bar at level 3 and the bar with all five parts.

Space z is focus mode: it hides the bar, the tabs and the one line, and shows them again.

## Colour

Pages are drawn without colour. Bold and dim stay; the only colour is red, on an open todo (its TODO badge, its tray and its box). A done todo is plain. The rule lives in `sgr` of the notation project (`boxview.rs` and `view.rs`); rebuild the notation binary and the hot path after a change.

## Find

Space / opens the find layer, and the popup lists its keys. fzf runs over what you pick: the first key is the scope, the second the kind. The pick opens as a tab and the point jumps to its line. The terminal belongs to fzf while it runs; escape in fzf comes back with nothing picked.

| Keys | Searches |
|---|---|
| f t, f b, f d | the open file: its text, its block types, its todos |
| p t, p b, p d, p n | the project: text, block types, todos, file names |
| w t, w b, w d, w n | the workspace: text, block types, todos, file names |
| escape | back to the visual layer |

The rows show paths relative to the folder searched, and the top of the screen previews the file: a page (.aiu) drawn as boxes the way the editor draws it, any other file as numbered lines around the picked line with a mark on it. Text covers every file of the scope. Block types and todos read the pages (.aiu). It needs fzf and rg; without fzf the key says so.

## 7. Build and check

~~~
PLTCOMPILEDROOTS="$HOME/aiu-compiled" raco make editor/src/entry/cli.rkt
nu gate/check.nu
~~~

No `compiled/` folder and no backup file may sit inside the tree.

## 8. Todo

| State | Item |
|---|---|
| done | first paint 0.8 s for a file and for the home screen |
| done | the send code loads on first use, and the real command lands in the table |
| done | the home screen scans in the background and repaints by itself |
| done | gate green, 17 stages |
| open | cut the 1.3 s between first paint and ready: `json` and `racket/port` load at start, replace them or load them later |
| open | lower the priority of the background scan, so typing never stutters while it runs |
| open | try the home keys by hand: 1 to 9, space q |
| open | try by hand that a page picked on the home screen opens as a normal session |
| done | the quick screen draws an .aiu page as boxes (not tried by hand) |
| open | the hot path binary lives in `/tmp`; rebuild it or set `AIU_HOT_PATH_BIN` if `/tmp` is cleared |
| open | try the block cursor by hand: up and down, w, i, typing, escape |
| open | the block cursor matches boxes to blocks by counting them level by level; a comment that wraps blocks may be drawn another way, and then its parent block is lit |
| open | a raw line wider than the screen is wrapped at a space behind the left edge of its box while a block is edited |
| open | the scan limits (800 pages, 8 repositories, 4 folders deep) are fixed in code |
| open | the project and workspace rows of the tab bar show where the page is; they do not switch yet |
| open | try by hand: the picks in visual (a p e c k l x o d), h and t by pick, the sub-mode in the bar and in the one line |
| open | after moving blocks the cursor cannot land on the todo tray of a box, so the todo cannot be selected from its box |
| open | try by hand: the bar (space b), the tabs (space t), focus (space z), find (space /) and the red-only colour |

## 9. Repo map

| Path | Holds |
|---|---|
| `README.md` | this guide |
| `README-AI.md` | guide for AI agents |
| `editor/src/entry/` | `quick.rkt` first screen, `cli.rkt` loader, `lean.rkt` file and home session, `cli-full.rkt` every other verb, `live.rkt` the live loop |
| `editor/src/dashboard/` | the home screen and the explorer |
| `editor/src/join/` | the seam to the Rust hot path |
| `editor/src/commands/` | the command table |
| `gate/` | the light gate |

## 10. Future plans

| Plan | Idea |
|---|---|
| tab completion for .aiu | one completion core: given the page text and the point, it answers candidates by context. Block names at a line start, with a snippet that writes the start line, the end line and puts the point between. Allowed values after kind:, language: and todo:. Tags already used across pages after tags:. Block names and declarations should be read from the notation engine, not copied. |
| completion key | in the write layer tab is the trigger, so the likely key is tab tab, with escape as the way out of the layer |
| completion in the editor | a complete command in the write layer, loaded on first use like the send key, so the first paint is untouched |
| LSP | a small separate stdio server that answers textDocument/completion with the same core, so Emacs (eglot) and other editors get the same completion. Built after the in-editor version. |

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

## 15. Plan: undo from git commits (owner decision, replaces the idea of section 14.2 to 14.5)

Status: step 1 built (section 17), the rest planned. The owner chose this design. Read section 14.1 first: it says what journal::archive does. First check that its patch applied (grep archive in editor/src/journal/journal.rs, and look for .base and .history files beside the journal). The history file may become unnecessary; ask the owner before deleting it.

### 15.1 Idea

Every change is autosaved, and every autosave becomes a git commit. The commit message is the file name plus the change, for example: test.aiu: +3 -1 lines in paragraph. Undo is a walk through those commits. The undo view is a tree of commits with their diffs.

### 15.2 Hard rule conflict, solved with a shadow repository

README rule: never use git in the project repo (it holds other projects, never git add -A). So the commits go in a PRIVATE repository outside the tree, for example ~/.aiu-undo/repo.git, driven with --git-dir=~/.aiu-undo/repo.git and --work-tree=/ (or the folder of the file). The project repo is never touched. Only the one saved file is added each time (git add -- FILE), never -A. Ask the owner to confirm this reading of the rule before building.

### 15.3 Commits

- Run in a background thread, after paint-ready, never on the key path. Debounce: commit about 1 s after the last edit, so typing a word is one commit.
- Triggered by edit-hook (hot-path.rkt, already called after every autosave) which marks the file dirty; one worker thread does the commits in order.
- Message: FILE NAME + change. The change text comes from git diff --shortstat and the block name at the point (page-of is cached).
- A file with no change makes no commit. Check that git commit has user.name and user.email set in the shadow repo config (set them at creation).
- The commit must not slow the page: measure a key press before and after (lesson 6 of the lessons section).

### 15.4 Undo and redo

- Undo = write the file content from the previous commit (git show COMMIT:PATH), through the normal edit ops so the editor state stays right, and make a NEW commit on top. Undo is itself undoable and nothing is lost.
- Branches: when the owner undoes and then edits, the new commit goes on a git branch from the old commit. The undo tree is the commit graph. git worktree is an option for opening an old branch beside the current one (split view, section 14.6); the plain shadow repo with branches is enough for the first version.
- Keys (ask the owner): u undo, r redo, a tree key (space u is level-up today, ask first). Each key needs a row in normal-keys, a command and a menu-groups row, or the gate goes red.

### 15.5 Undo view

- A tree of commits for the open file: git log --graph --oneline -- FILE, one line per commit with time and message, walked with h and t, a diff of the lit commit shown beside or below (git diff COMMIT^ COMMIT -- FILE).
- First version: run it through run-picker (finder.rkt) with fzf and a preview script, like find does; a pick restores that commit. Second version: draw it as an AIU page in the editor with the notation view.
- Everything must wrap to the screen width (owner rule for terminal and tv previews).

### 15.6 Build steps

| Step | Work |
|---|---|
| 1 | shadow repo created on first use in a thread; commit worker with debounce; message builder |
| 2 | undo and redo keys, a new commit on top, notification of what was restored |
| 3 | fzf tree view with diff preview (git log --graph, git diff) |
| 4 | branches on edit after undo, the tree shown with branch marks |
| 5 | git hunk and block revert from the git strip (gutter.rkt), restore from a commit |
| 6 | optional: git worktree to open an old state beside the current one; pruning of old commits |

### 15.7 Rules for the build

Lazy: new module loaded on first use, never required by quick.rkt, cli.rkt, lean.rkt, live.rkt or home.rkt except through a stub. No hot path request on a key press. One script per step, compile, gate, then the owner holds h or t and says if it is smooth. Update both READMEs in the same script. Scripts: one bash -c block, nothing after the closing quote, no single quote inside.

### 15.8 Questions for the owner

1. Is the shadow repository outside the project acceptable under the never git rule?
2. One commit per debounced edit burst, or one per save of the page?
3. Keep the history file of section 14, or drop it once commits exist?

## 16. Work rules: always update the READMEs, commit with git, no backup files

Owner decision (2026-10-31). It replaces the copies in /tmp as the way to backtrack. The old rule "never git" is relaxed for THIS workflow only: the repo holds other projects, so git is used with explicit paths and never with add -A, add . or commit -a.

### 16.1 Every change, in this order, inside the same script

1. Before patching: commit the files the script will touch, exactly as they are now, so the state before is saved.
   git add -- FILE1 FILE2 README.md README-AI.md
   git commit -m "before: FILE1 FILE2: what is about to change" -- FILE1 FILE2 README.md README-AI.md
   If nothing changed, git commit fails with nothing to commit: that is fine, go on.
2. Patch the files and update README.md and README-AI.md in the same script, every time.
3. Compile. If it fails, restore ONLY the touched files: git checkout HEAD -- FILE1 FILE2 README.md README-AI.md and compile again. No copies in /tmp.
4. If it compiles, commit the result with the file names and the change as the message:
   git add -- FILE1 FILE2 README.md README-AI.md
   git commit -m "FILE1 FILE2: what changed" -- FILE1 FILE2 README.md README-AI.md
5. Run the gate only when the owner asks or after a bigger step, and commit again if the gate made you fix something.

### 16.2 Rules

- Pathspec always. Never git add -A, git add ., git commit -a, git reset --hard, git clean, git checkout . or git stash: other projects live in this repo.
- New files: git add -- the exact path. Deleted files: git rm -- the exact path.
- Commit message format: FILES: change, in one line, under 100 characters. Prefix before: or after: only when it helps.
- Backtrack one file: git checkout COMMIT -- FILE. See the history of a file: git log --oneline -n 15 -- FILE. See what a step changed: git show --stat COMMIT.
- Do not push, pull, branch or amend unless the owner asks. The owner pushes.
- No backup files anywhere. Scratch scripts still live in /tmp and are deleted at the end of the script.
- If git fails (lock file, not a repository), print the real error, go on without it for that step and tell the owner. Do not fall back to backup copies in the tree.
- The undo from commits in section 15 is a different repository (the private shadow one). This section is only about how the AI changes the code.

### 16.3 Shell reminder

All of the above goes inside the one bash -c block, with git commands joined by semicolons or on separate lines, nothing after the closing quote, no single quote inside, and git messages in double quotes.


## 17. Undo commits on the branch aiu-undo (step 1 of section 15, rebuilt 2026-10-31)

Code: `editor/src/dashboard/shadow.rkt` (file name kept, racket/base only). `save-after` in `join/hot-path.rkt` calls `shadow-note!` with the saved file; that starts a thread which loads the module on first use. It is listed in `compile-deps` of `entry/cli.rkt`, so raco make builds it. One worker commits 1 s after the last note, so a burst of typing is one commit.

The commits go on the branch `aiu-undo` of the git repository that holds the saved file. The branch starts empty and shares no history with main, so plain git log on main never shows it. Read it with `git log aiu-undo`, or `git log aiu-undo -- FILE` for one file. The editor never checks it out. Each commit is built with plumbing and a private temporary index file in the git folder (read-tree of the branch, hash-object, update-index, write-tree, commit-tree, update-ref), so the real index, HEAD and work tree are never touched. If HEAD is on aiu-undo the commit is skipped and logged. A file outside a git repository is skipped. The message is NAME: +A -D lines. No change, no commit. Errors go to `~/.aiu-undo-error.txt`, never to the screen.

Decisions: branch inside the main repo (the owner preferred it to a separate shadow repository, which was deleted), one commit per debounced burst, history file kept. git push --all would push the branch, so push it only on purpose.

Not built yet: undo and redo keys, the tree view, branches for edits after an undo, the block name in the message, worktrees, pruning.

Interim 2026-10-31: the shadow-note! call was taken out of save-after, so nothing commits while typing. It will be wired to leave-write (escape in the write layer).
