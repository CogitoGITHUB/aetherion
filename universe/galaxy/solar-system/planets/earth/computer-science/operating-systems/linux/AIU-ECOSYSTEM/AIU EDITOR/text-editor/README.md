# AIU EDITOR

A terminal text editor written in Racket with a Rust hot path. It is built so a
file is on the screen in under a second, and everything else loads behind it.

AI agents: read README-AI.md first, not this file.

## 1. Lazy loading: the main feature

The rule is open first, load later. The file is drawn before anything else is
loaded, you can type at once, and the rest of the editor arrives while you work.

| Moment | What happens | Measured on the phone |
|---|---|---|
| first paint | the first lines of the file are drawn, with a mode line that says the editor is loading | 0.8 s (was 2.1 s) |
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
| up, h | on a page: light the block before |
| down, t | on a page: light the block after |
| left, n | move the point left |
| right, s | move the point right |
| w | on a page: write the lit block as raw text, markers shown (see Block editing) |
| i | on a page: edit only the text of the lit block, inside its drawn box |
| m | the move layer |
| backspace | take back the character before the point |
| escape | stay in the visual layer |
| space f | the write layer on the whole page, raw |
| space v | the select layer |
| space s | save |
| space q | quit |
| space l | show |
| space d, space u | show one level less or one level more of the rows of the editor (0 to 3) |
| space ? | the explorer |
| space g | send (loads its code on first use) |
| space b | the bar layer (see Bar) |
| space t | the tab layer (see Tabs) |
| space / | find with fzf (see Find) |
| space z | focus mode: hide the bar, the tabs and the one line, and again to bring them back |
| space k | check (pages) |
| space n, p, e | next block, previous block, block end |
| space r | view the page as a reader; on the home screen, scan again |
| 1 to 9 | on the home screen, open that page |
| space, then wait | pops up two tables over the bottom rows of the page: table 1 the keys that can follow in the active layer, table 2 the modes with the key that enters each and its trigger, both read from the key tables |

Write layer (keys are text, tab is the trigger):

| Key | Does |
|---|---|
| tab tab | back to the visual layer |
| tab s, tab q | save, quit |
| tab v | the visual layer |
| tab b, tab k | blocks, check |
| tab r | view |
| tab n, tab p | next block, previous block |
| escape | save, then back to the visual layer |
| up, down, left, right | move the point |
| backspace | take back the character before the point |

Select layer (reached with space v):

| Key | Does |
|---|---|
| space space | the write layer |
| space s, space q, space g | save, quit, send |
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
A plain text file still scrolls with up and down.

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
| h, left | the tab before |
| t, right | the tab after |
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
| open | try the home keys by hand: space r, 1 to 9, space q |
| open | try by hand that a page picked on the home screen opens as a normal session |
| open | the quick screen shows an .aiu page as raw text until the editor is ready |
| open | the hot path binary lives in `/tmp`; rebuild it or set `AIU_HOT_PATH_BIN` if `/tmp` is cleared |
| open | try the block cursor by hand: up and down, w, i, typing, escape |
| open | the block cursor matches boxes to blocks by counting them level by level; a comment that wraps blocks may be drawn another way, and then its parent block is lit |
| open | a raw line wider than the screen is wrapped at a space behind the left edge of its box while a block is edited |
| open | the scan limits (800 pages, 8 repositories, 4 folders deep) are fixed in code |
| open | the project and workspace rows of the tab bar show where the page is; they do not switch yet |
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
