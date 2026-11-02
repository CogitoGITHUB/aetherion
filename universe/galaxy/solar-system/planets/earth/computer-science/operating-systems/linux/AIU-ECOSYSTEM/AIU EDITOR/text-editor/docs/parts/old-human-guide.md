
## Human guide from the old docs (copied 2026-11-01, keys, home screen, bar, tabs, colour, find)

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
| space v | the select layer (section 21) |
| space c | the cursor layer (section 21) |
| space s | save, then one undo commit (nothing is saved while typing) |
| space q | quit |
| q | quit |
| space u | the undo layer (section 20) |
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

Code: `editor/src/tui/notify.rkt` (racket/base and box.rkt only). `notify!` takes a level (info, warn, error) and a text; the box stays 2, 3 or 5 seconds, an identical text replaces the old one, at most 3 show. `notify-overlay` is added to the overlay of the paint in `repaint-now` (`live.rkt`), below a top bar or tabs, and a thread repaints through `notify-repaint` when one expires. An unbound key says no key and the keys of the sequence, with the sub-mode. Errors are drawn red.

## Paint without flicker

`paint` in `screen.rkt` no longer clears the screen. It homes the cursor, puts an erase of the line before every row (`erase-lines`) and wraps the frame in the synchronized update codes `sync-begin` and `sync-end` (`?2026h`, `?2026l`), which a terminal that does not know them ignores. The bar, the tabs and the page are overwritten in place, so nothing blanks between keys. `quick.rkt` still clears once for the first paint.

## Popup pick box

In the visual layer the SPC popup has a box named pick with the keys a p e c k l x o d, built from `normal-keys` (the commands that start with kind-). The title of the popup shows the sub-mode, for example visual general [any].

## State after the session of 2026-10-31

- Gate green, 17 stages. Kind layer removed: the picks are plain keys in visual (a p e c k l x o d), sub-modes visual general, visual navigation, visual selection, shown in the bar, the side strip, the one line and the SPC popup (a pick box and the sub-mode in the title).
- Notifications: `tui/notify.rkt`, an unbound key shows a warn box top right instead of printing over the page.
- Paint no longer sends the clear code: it homes the cursor, erases each line and wraps the frame in ?2026h and ?2026l (`screen.rkt`). Only `quick.rkt` clears, once. The timing loop that waits for the clear code still sees the first paint only.
- `quick.rkt` draws an .aiu page as boxes through the notation binary (`boxed-lines`, subprocess only, raw text when it fails) and says nothing about loading. Keys typed meanwhile queue and run when the editor is ready.
- machine/small.rkt exists but nothing requires it. The start path uses racket/path and racket/port. The swap felt slow on the phone, so measure a keypress before trying it again.
- Open: the owner reported flicker and slow movement after the quick-screen and small.rkt changes. Test by hand after any paint or start change. If it returns, revert the flicker patch in screen.rkt next.
- Open: still about 1.3 s from first paint to ready (json in protocol.rkt is needed for the first hot path message, so lazy json gains nothing; racket/path costs about 0.7 s, racket/port 0.4 s on this phone).

## Hot path answer cache

`ask-hot` in `join/hot-path.rkt` keeps the answers of the read requests notation, show, notation-render and notation-view, and clears all of them before and after any other request. A repaint asked the hot path 3 or more times per key (about 1.35 s a key on the phone); now it asks once. A new read-only operation may be added to `read-ops`; a new operation that changes text needs nothing.

## Git strip

`tui/gutter.rkt` keeps the hunks of `git diff -U0` for the open file, asked in a thread (4 s after the first ask, then every 15 s or when the file changes). `tui/gutterview.rkt` puts one column at the left of every drawn line of an .aiu page: plus for added, equals for changed, minus for removed, on the lines of each leaf block that a hunk touches (`bv-ranges`, exported by `blockview.rkt`, maps blocks to drawn lines). `repaint-now` in `live.rkt` takes one column off the page width for it. Lines are matched by the saved file, so unsaved edits can shift a mark until the next refresh. A removal between two blocks puts a minus on the first drawn line of the block after the gap (git reports it at the line before the gap), a removal inside a block marks the block equals. A swap of two blocks shows as plus on one block and minus at the gap, because git describes it that way. Only glyphs, no colour.

## Save and commit by hand

Nothing is saved or committed while you type. An edit op (type, delete, delete-at, insert-at) only changes the text in the hot path and calls `dirty-hook`, which sets the box `unsaved` (`commands.rkt`); `live.rkt` installs it. The edits stay in the journal until a save, so a quit with unsaved edits loses nothing. The `save` command (space s, tab s) is wrapped at the end of `blockview.rkt`: it saves, clears `unsaved`, then `bv-after-write` runs `edit-hook` (git row, strip and tab git text marked old) and notes the file for `shadow.rkt`, which makes one undo commit on the branch aiu-undo. Escape in the write layer saves and commits the same way. While `unsaved` is true the git row, the git strip and the tab git text are not refreshed. The bar part `save` replaces the git part in `bar-order`: it shows `unsaved  SPC s saves` only when `unsaved` is true and takes no row otherwise; the one line adds `unsaved: SPC s`. This section replaces the old Autosave text and the trigger text of sections 17 and 18.
## Git row and git in the tabs

`git-facts` (`bar.rkt`) answers branch, changed files, ahead, behind, last commit, then staged files, unstaged files, inserted lines and deleted lines (`git diff --shortstat HEAD`). `git-text` shows them in the git row of the bar. The git thread also sets `tab-git-text` (`tabs.rkt`), and `tab-rows` ends every tab bar, at all three levels, with a git section holding that text. Both are filled 4 s after start. Untracked files are still not counted.

## Git starts after the page is shown

No timer. `paint-ready` (`box.rkt`) is set by `live-session` right after the first full paint; `git-refresh-maybe` (bar.rkt) and `gutter-refresh-maybe` (gutter.rkt) do nothing until it is true, and one more repaint is started in a thread so they begin at once. Rule from the owner: once the page is shown and can be worked on, everything else may run in the background. Any older text in this file about waiting 4 s is obsolete.

## Bar

Space b opens the bar layer, and the popup lists its keys. The bar has five parts: the layer, the time, git, the date and the keys. It stands at the bottom or the top as a box, or on the sides as strips with the letters upright: docked beside the page, or floating over it. With both sides the layer, git and the keys are on the left, and the time and the date on the right. A screen under 14 rows keeps the one old line. The time is read at each paint, and git is asked in a thread every 20 seconds, never in a paint.

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
PLTCOMPILEDROOTS="$HOME/aiu-compiled" raco make editor/src/entry/cli.rkt editor/src/tui/undo.rkt editor/src/tui/multi.rkt editor/src/tui/clip.rkt
nu gate/check.nu
~~~

No `compiled/` folder and no backup file may sit inside the tree.

