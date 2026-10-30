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
| nushell | for the gate | `nu gate/check.nu` |

## 5. Keys

The trigger is space. Nothing needs a modifier key.

| Key | Does |
|---|---|
| w | on a page in the visual layer: write the lit block as raw text, markers shown (see Block editing); tab is the trigger in the write layer |
| space f | the write layer on the whole page, raw |
| space s | save |
| space q | quit |
| space r | view the page as a reader; on the home screen, scan again |
| space b, k | blocks, check (pages) |
| space n, p, e | next block, previous block, block end |
| space g | send (loads its code on first use) |
| space | waits for the next key and pops up two tables over the bottom rows of the page: table 1 the keys that can follow in the active layer, table 2 the modes with the key that enters each and its trigger (SPC is the space key), both read from the key tables |
| escape | in the write layer: save, then back to the visual layer; in the move layer: back to the visual layer |
| h, t | on a page in the visual layer: light the block before or after |
| n, s | move the point left or right |
| m | the move layer: h and t swap the lit block with the one before or after it, escape leaves |
| up, down | on a page in the visual layer: light the block before or after |
| i | on a page in the visual layer: edit only the text of the lit block, inside its drawn box; escape draws the page again |
| 1 to 9 | on the home screen, open that page |

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
Space f writes the whole page raw. Space space and space w are no longer keys.
A plain text file still scrolls with up and down.

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
