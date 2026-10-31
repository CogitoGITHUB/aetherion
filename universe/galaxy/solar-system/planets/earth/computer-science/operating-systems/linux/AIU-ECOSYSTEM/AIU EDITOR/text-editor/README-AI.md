# AIU EDITOR: guide for AI agents

Read this whole file before doing anything. It is the working contract for any
AI that changes this package. It holds the todo list, so one cat of this file is
enough.

## 1. Hard rules

| Rule |
|---|
| Lazy loading is the main feature. Never slow the first paint (section 2). |
| No `.org` files and no `compiled/` folders inside the tree. |
| Compile with `PLTCOMPILEDROOTS="$HOME/aiu-compiled"`. |
| `aiutd` must never create or seed a file from `AIU NOTATION/types/default.aiu`. |
| Never create backup files. Scratch goes in `/tmp`. |
| Give all commands in ONE code block per reply, wrapped as `bash -c` (section 4). |
| Use paths relative to the folder the user is in. |
| Whenever a change needs a README update, put it in the same script, every time. |
| Close every gap in the same script. Ask for all the code needed up front, in one request. |
| Replies are short: the owner reads on a phone. Show real output, never say it works without it. |
| Do not edit `AIU NOTATION`. Read it only, unless the owner asks for the change in that request (the colour change was one). |
| Comment above every definition, header comment on every file. The gate enforces it. |

## 2. Lazy loading contract

Measured on the phone (2 cores): first paint 0.8 s for a file and for the home
screen, down from 2.1 s. Editor ready about 2 s. A quit typed at once quits.

| Stage | Module | Rule |
|---|---|---|
| first paint | `entry/quick.rkt` | `racket/base` only. Draws the file head, turns echo and line mode off so keys queue, gives them back at exit. |
| loader | `entry/cli.rkt` | requires only `quick.rkt`. `compile-deps` submodule builds the rest. Loads `lean.rkt` or `cli-full.rkt` with `dynamic-require`. |
| live edit | `entry/lean.rkt` | on a terminal with the edit verb. Commands, keys, screen, home screen. No send, audit, checkpoint, plugin, mcp. |
| every other verb | `entry/cli-full.rkt` | scripted runs (input not a terminal) and all other verbs. The gate proofs read this one. |
| agent side | `send/send.rkt` | loaded by the stub of the send key on first press; it puts the real command in the table. |
| home screen | `dashboard/home.rkt` | shows the kept scan at once, scans in a thread after the first paint, repaints itself. Does not start the hot path. |

Rules for changes:

- Never add a require for send, audit, checkpoint, plugins, mcp, `json`, `net/url` or `racket/port` to `quick.rkt`, `cli.rkt`, `lean.rkt`, `live.rkt` or `home.rkt` without measuring. A heavy feature loads on first use, the way the send stub does.
- Anything slow after the first paint runs in a thread and repaints itself. Nothing waits for a scan.
- A change to the start path ends with the timing run below, and the first paint must stay under 1 s.

~~~
t() { start=$EPOCHREALTIME; paint=""; buf=""; ( sleep 5; printf " q" ) | timeout 20 script -qec "aiutd $1" /dev/null | while IFS= read -r -n1 -d "" c; do buf+="$c"; case "$buf" in *$(printf "\033[2J")*) if [ -z "$paint" ]; then paint=1; echo "$1 first paint: $(awk "BEGIN{printf \"%.1f\", $EPOCHREALTIME-$start}") s"; fi;; esac; done; }
t editor/README.md; t ""
~~~

Do not time "editor ready" with that loop: it rescans the growing output and
reports a number far too high. Time keys typed at once instead: `printf " q" | script -qec "aiutd FILE" /dev/null`.

## Block cursor and block edit

Code: `editor/src/dashboard/blockview.rkt`. The live screen asks it, in `live.rkt`,
for `block-overlay` (what to draw), `block-guard` (wraps every command) and
`drawn-view` (the notation drawing, kept for the same text and width). The keys
are in `keymaps.rkt`: h and t are `block-up` and `block-down`, w is
`block-edit`, i is `block-text`; a file that is not a page scrolls as before.
`commands.rkt` also provides `move-to`.

How it works, and what to keep true:

- The page parse gives every block its byte range; the notation drawing gives boxes. The drawing is read as boxes (a top edge, a bottom edge, a second bottom edge when a todo tray follows) and matched to blocks level by level, in order. A level whose counts differ is left unmatched, so a block never gets the wrong lines.
- Answers are not drawn, and the first title of a section is the name on the top edge of the section box.
- The lit block is the innermost block at the point whose lines are known. It is lit in reverse video; the view follows it.
- w (`block-edit`, `bv-edit-overlay`): the layer becomes write, the block box is replaced by its raw bytes with start and end lines, behind the left edge of the parent box (`bv-prefix` of the depth) cut at a space by `bv-chunks` to the box width, padded by `bv-pad`, with the right edges of the parent boxes drawn on every line; the rest stays drawn. `edit-mode` is raw and `edit-lo` is the block start.
- i (`block-text`, `bv-text-overlay`): the layer becomes write, the top and bottom edges of the box stay drawn, and only the text lines between the start and end lines are shown raw inside the box, behind the left edge of the box, each line cut at a space to the screen width by `bv-chunks`, with the left edge drawn on every part, each part padded and closed by the right edge. `edit-mode` is text and `edit-lo` is the first text byte; the point is clamped to the text range (`bv-content`, `bv-hi`). A block that holds other blocks, or has no text line, opens as w does.
- The point is clamped inside the edit range after every command, and the backspace at the start of the range is refused. Leaving the write layer ends the edit. A block that can no longer be found ends the edit and shows the whole raw page.
- Keys: w runs `block-edit`, i runs `block-text`; space f is the whole-page write layer (`write-mode`). Space space is bound only in the select layer (`mode`); space w is not a key.
- Cost: one extra page parse request on each repaint of a page. Nothing here loads before the first paint.
- The notation project is not touched; if its drawing changes shape, fix the reading of boxes in `blockview.rkt`.

## Block move, keys and menu

Keys in `keymaps.rkt`: h and t are `block-up` and `block-down`, n and s are `move-left` and `move-right`, m is `block-move-mode`. The move layer (`move-keys`, trigger space) has h and t as `block-move-up` and `block-move-down` and escape back to visual. `bv-move` in `blockview.rkt` swaps the lit block with its sibling (`bv-siblings`: same parent, answers and titles never move) by one delete-at and one insert-at, and the point follows the block. Escape in the write layer runs `leave-write`: save, then the visual layer. In `live.rkt`, `pending-keys` holds the keys of a waiting sequence and `menu-text` draws two boxes, the modes table and the keys in group boxes, at most 66 wide; `menu-float` centers them and `menu-screen` blanks the page behind them and puts them in the middle rows (`text-shown`), with the point at the start of the menu so nothing scrolls. The modes table lists every layer with an enter key (`enter-key`, found in the visual keys by the command name ending in the layer name and -mode) except the active one, and the keys box holds the keys of the active layer in group boxes. The groups, the words and the order come from `menu-groups` and `menu-group-order` in `live.rkt`; a command missing there sits in the keys group under its own name. `menu-box` and `menu-cells` draw them.

## Keys by layer

Source of truth: `keymaps.rkt` (`normal-keys`, `insert-keys`, `select-keys`, `move-keys`, `trigger-of`). Keep README.md section 5 in step with it.

| Layer | Trigger | Keys (command) |
|---|---|---|
| visual | space | w block-edit, i block-text, h block-up, t block-down, n move-left, s move-right, m block-move-mode, backspace delete, escape visual-mode, space f write-mode, space v select-mode, space s save, space q quit, space u level-up, space ? explorer, space g send, space b bar-mode, space t tab-mode, space z focus-toggle, space / find-mode, a any, p paragraph, e section, c code, k comment, l title, x todo, o todo open, d todo done, space k check, space n next-block, space e block-end |
| write | tab | tab tab mode, tab s save, tab b blocks, escape leave-write, up move-up, down move-down, left move-left, right move-right, backspace delete |
| select | space | space space mode, space v visual-mode, escape visual-mode |
| move | space | h block-move-up, t block-move-down, escape visual-mode |
| bar | space | p bar-place-next, b bar-bottom, u bar-top, l bar-left, r bar-right, s bar-sides, d bar-style, x bar-hide, v bar-level-mode, escape visual-mode |
| bar-level | space | h bar-less, t bar-more, escape bar-mode |
| tab | space | h tab-prev, t tab-next, o tab-open, c tab-close, p tab-place-next, u tab-top, b tab-bottom, j tab-join, x tab-hide, v tab-level-mode, escape visual-mode |
| tab-level | space | h tab-less, t tab-more, escape tab-mode |
| find | space | f t, f b, f d: file text, blocks, todos; p t, p b, p d, p n and w t, w b, w d, w n: project and workspace text, blocks, todos, files; escape visual-mode |

On the home screen the keys 1 to 9 open that page (`live.rkt`).
## Pick filter

Code: `kind-filter` (a box, end of `commands.rkt`) holds any, a block name, todo, todo open or todo done; `mode-label` names the sub-mode. The picks are plain keys in `normal-keys`: a any block, p paragraph, e section, c code, k comment, l title, x any todo, o open todo, d done todo. `bv-step` in `blockview.rkt` keeps only the blocks `bv-kind-match?` accepts, so h and t (block-up, block-down) move between blocks of that kind. `bv-todo-state` reads the todo declaration: the first word after todo: is done or open, no word is open. Sub-modes: visual general (pick any), visual navigation (other pick), visual selection (select layer). The mode line is `mode-label` plus the pick, for example `visual navigation [todo open]`, in `bar-rows` and `cell-chars` (`bar.rkt`) and in the one line (`repaint-now`, `live.rkt`). There is no kind layer and no space j. The menu-groups rows kind and todo stay for the commands.

## Notifications

Code: `editor/src/dashboard/notify.rkt` (racket/base and box.rkt only). `notify!` takes a level (info, warn, error) and a text; the box stays 2, 3 or 5 seconds, an identical text replaces the old one, at most 3 show. `notify-overlay` is added to the overlay of the paint in `repaint-now` (`live.rkt`), below a top bar or tabs, and a thread repaints through `notify-repaint` when one expires. An unbound key says no key and the keys of the sequence, with the sub-mode. Errors are drawn red.

## Paint without flicker

`paint` in `screen.rkt` no longer clears the screen. It homes the cursor, puts an erase of the line before every row (`erase-lines`) and wraps the frame in the synchronized update codes `sync-begin` and `sync-end` (`?2026h`, `?2026l`), which a terminal that does not know them ignores. The bar, the tabs and the page are overwritten in place, so nothing blanks between keys. `quick.rkt` still clears once for the first paint.

## Popup pick box

In the visual layer the SPC popup has a box named pick with the keys a p e c k l x o d, built from `normal-keys` (the commands that start with kind-). The title of the popup shows the sub-mode, for example visual general [any].

## Lessons for the next AI (read before you reply)

1. Nushell: the whole command is ONE bash -c with single quotes, and NOTHING may follow the closing quote. A trailing 2>&1 or pipe outside the quotes makes Nushell refuse to parse and nothing runs. Put redirects and pipes inside, for example { ...; } 2>&1 | fold -s -w 56 inside the quotes. No single quote anywhere inside, not even in comments or text (write do not, never do not).
2. Tokens: the owner is on a phone and pays for every round. Ask for ALL the reads in one request, narrow (grep -n, sed -n ranges). Do not run measuring loops nobody asked for. Terminal pastes wrap and lose the top lines, so end each read with cut -c1-110 and head, and print the verdict lines last.
3. Gate output: nu gate/check.nu prints the CALLER lists of security-gate, which look like errors. Look for lines that start with COMMENT, FAIL or the words red, or the last line (light gate: green). A patch that inserts helpers right after a definition can split it from its comment and fail comment-lint: put the helper above the comment of the definition, never between.
4. Every script that touches several files: read all files into memory, check every anchor occurs exactly once, write nothing otherwise, keep copies in /tmp, and restore them if compile or gate fails. README anchors are optional.
5. Timing: bare racket starts in 0.3 s, loading lean.rkt takes about 1.5 s, first paint 0.8 to 1.3 s. A loop that times the whole run includes the quit and the hot path teardown and reads 4 to 6 s: it is NOT the time until keys work. Never judge a change by it, and never when the owner has other things running (check /proc/loadavg).
6. A change that passes the gate can still make movement slow or flicker. The gate does not feel keypresses. After any change on the paint or start path, ask the owner to hold h or t and say if it is smooth, before more changes.
7. The owner rules: the file is shown first and keys work at once, everything else loads in the background; no loading message; no whole-file cats; short replies; real output only; no git; no backup files in the tree.
8. Unbound keys: plain letters in a reading layer used to be dropped silently; they now raise a notification. Messages must never be printed over the page.

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

## Hot path answer cache

`ask-hot` in `join/hot-path.rkt` keeps the answers of the read requests notation, show, notation-render and notation-view, and clears all of them before and after any other request. A repaint asked the hot path 3 or more times per key; now it asks once. A new read-only operation may be added to `read-ops`; an operation that changes text needs nothing. Measured before: about 0.33 s a key (20 keys 11.9 s, 0 keys 5.2 s).

## Git waits after the first paint

The git thread in `git-refresh-maybe` (`bar.rkt`) sleeps 4 s before it runs git. Found by timing: git started by the first repaint competed with the notation view call of the hot path on 2 cores, and that call took 1.8 s instead of 0.05 s, so the editor looked frozen and the first keys waited. Lesson: put a logging wrapper in AIU_NOTATION_BIN and a fake git on PATH to find who competes, before changing code.

## Git strip

`dashboard/gutter.rkt` keeps the hunks of `git diff -U0` for the open file, asked in a thread (4 s after the first ask, then every 15 s or when the file changes). `dashboard/gutterview.rkt` puts one column at the left of every drawn line of an .aiu page: plus for added, equals for changed, minus for removed, on the lines of each leaf block that a hunk touches (`bv-ranges`, exported by `blockview.rkt`, maps blocks to drawn lines). `repaint-now` in `live.rkt` takes one column off the page width for it. Lines are matched by the saved file, so unsaved edits can shift a mark until the next refresh. Only glyphs, no colour.

## Autosave

Every hot path request that changes text (type, delete, delete-at, insert-at) is followed by a save of the same file (`ask-hot`, `join/hot-path.rkt`, `edit-ops`, `save-after`), so git sees the change. `edit-hook` then marks the git row (`git-stale!`, bar.rkt) and the git strip (`gutter-stale!`, gutter.rkt) old, and the next paint asks git again. The 4 s wait applies only to the first git ask. Unsaved edits no longer exist in normal use; check what save does to the journal before relying on undo.

## Bar

Code: `editor/src/dashboard/bar.rkt` (state `bar-place`, `bar-saved`, `bar-style`, `bar-count`; `bar-plan-of`, `bar-rows`, `strip-lines`, `git-refresh-maybe`; the commands `bar-mode`, `bar-level-mode`, `bar-place-next`, `bar-bottom`, `bar-top`, `bar-left`, `bar-right`, `bar-sides`, `bar-style`, `bar-hide`, `bar-less`, `bar-more`). The keys are in `keymaps.rkt` (`bar-keys`, `bar-level-keys`; layers `bar` and `bar-level`, entered with space b). `explorer.rkt` requires `bar.rkt` so the gate sees the commands. `live.rkt` asks for one `bar-plan` in `repaint-now`: the page width and height are the screen minus the columns and rows of the plan, and `screen.rkt` `paint` takes `#:offset`, `#:left`, `#:full` and `#:overlay`. The popup also opens by itself in the layers bar and bar-level. A paint reads no file and asks no page; git runs only in a thread. The blocks command is no longer on space b: type it, or use tab b in the write layer.

## Tabs and focus

Code: `editor/src/dashboard/tabs.rkt` (state `tab-files`, `tab-current`, `tab-switch`, `tab-place`, `tab-count`, `tab-joined`; `tab-rows`, `tb-scan-maybe`; the commands `tab-mode`, `tab-level-mode`, `tab-prev`, `tab-next`, `tab-open`, `tab-close`, `tab-place-next`, `tab-top`, `tab-bottom`, `tab-join`, `tab-hide`, `tab-less`, `tab-more`), `box.rkt` (the box drawing shared with the bar) and `bar.rkt` (`bar-plan-of` makes one plan from the bar and the tabs; `focus-on`, `focus-toggle`). Keys in `keymaps.rkt` (`tab-keys`, `tab-level-keys`; layers tab and tab-level, entered with space t; space z is focus-toggle). A tab command sets `tab-switch` and returns false, which ends the round of `key-loop`; `live-session` (`next-round`) then opens that file with its own journal in the same terminal, the hot path and the wire staying up. `live-session` calls `tab-show!` for every file. The bar and the tabs at one edge are stacked (tabs first) and shared with `join-edge` when `tab-joined`; the tabs need 16 rows, the bar 14. The folders of the workspace and the project rows are listed in a thread once for each root (`tab-lists`); a paint reads no folder. Both bars start with every level shown: `tab-count` is 3 and `bar-count` is 5. Focus mode makes a plan of nothing: no bar, no tabs, no one line. No heavy require was added.

## Colour

The notation drawing (`boxview.rs`, `view.rs`, function `sgr`) drops every colour code below 30 or above, so only bold, dim, italic and underline pass; `sgr_todo` keeps red (31) for an open todo and nothing for a done one. The bar and the tabs are white text on the terminal background. After a change, rebuild the notation binary and the hot path (`CARGO_TARGET_DIR=/tmp/editor-target cargo build --manifest-path editor/Cargo.toml`).

## Find

Code: `editor/src/dashboard/finder.rkt` (`finder-script`, `run-picker`, `parse-pick`, `find-run`, `find-jump`, `line-start-offset`; the commands `find-mode` and `find-<scope>-<kind>`). Keys in `keymaps.rkt` (`find-keys`, layer find, entered with space /). A search builds one shell line (`rg` into `fzf`), `run-picker` restores the terminal (`restore-settings`, leave the alternate screen), runs it with `/bin/sh -c` and takes the terminal back (`raw-mode`). A pick sets `tab-switch` and `find-jump` and returns false, which ends the round of `key-loop`; `live-session` opens the file as a tab and moves the point to the line. Scopes: the folder of the file, the project folder (`tb-project-dir`), the workspace root (`tb-root`). `explorer.rkt` requires `finder.rkt` so the gate sees the commands. The rows are relative to the folder searched (the file scope searches its own file name from its folder), and fzf shows a preview made by a small sh script that `run-picker` writes to /tmp for the run and deletes after (`preview-script`, `preview-path`): an .aiu page drawn by `notation view` at the width of the preview (the binary is `notation-bin`, passed to the script as AIU_PREVIEW_NB, which `find-run` sets), any other file as the lines around the picked line with numbers and a mark. The preview stands at the top, 60 percent. Nothing runs in a paint.

## 3. Environment

| Variable | Effect |
|---|---|
| `AIU_ROOT` | folder the home scan starts from; `aiutd` sets it |
| `PLTCOMPILEDROOTS` | where compiled files live; `aiutd` sets it to `~/aiu-compiled`; without it every start recompiles for about 10 s |
| `AIU_HOT_PATH_BIN` | Rust hot path program; default `/tmp/editor-target/debug/hot-path` |
| `AIU_NOTATION_BIN` | notation binary; default under `AIU NOTATION/notation system/notation/target/debug/notation` |
| `LANG`, `LC_ALL` | `C.UTF-8`; the project path holds the letter Ae, and a child under the C locale gets it as question marks |

## 4. Shell compatibility

| Case | Rule |
|---|---|
| `aiutd` | POSIX sh, no bashisms; runs from bash, sh, zsh and nushell |
| owner shell | nushell; Nu syntax from AI has been unreliable, so give bash |
| snippets | wrap as `bash -c` with the whole snippet in single quotes; nushell then needs no `&&` |
| inside the wrapper | no single quote anywhere, in code or in comments |
| heredocs | `<<"EOF"` with double quotes, because single quotes break the wrapper |
| Racket patch scripts | write a script to `/tmp`, run it, delete it; use here strings for raw text |
| gate | `nu gate/check.nu` |
| noise | `raco` prints harmless "registered twice" warnings; filter them with `grep -v` |

## 5. Commands

Run from the `text-editor` folder.

| Task | Command |
|---|---|
| Compile | `PLTCOMPILEDROOTS="$HOME/aiu-compiled" raco make editor/src/entry/cli.rkt` (full path of raco: `/root/home/shape/opt/racket-full/bin/raco`) |
| Gate | `nu gate/check.nu` (17 stages) |
| Open a file | `aiutd FILE` |
| Home screen | `aiutd` |

## 6. Gate

Stages: paren-check, load-check, naming, one-way, security-gate, language-split,
comment-lint, route-check, explorer-check, key-check, notation-check,
dashboard-check, secret-check, kit-check, plugin-check, send-check, git-check.
A stage that checks nothing says NOTHING-TO-CHECK. comment-lint wants a comment
line above every definition.

## 7. Status

| Feature | State |
|---|---|
| quick first screen, keys typed during load kept | works, measured |
| lean live session, lazy send | works, measured |
| home screen drawn by the notation view, background scan, kept scan | works, measured |
| home keys (1 to 9, space q) by hand | not tried by hand |
| block cursor and block edit (up, down, w, i) | works in a test on the default page, not tried by hand |
| a page picked on the home screen opens as a normal session | not tried by hand |
| commands that need a file on the home screen do nothing | not tried by hand |
| scripted sessions and all other verbs | work through `cli-full.rkt`, gate green |
| bar, tabs, focus mode, find with fzf, red-only colour | built, gate green, not tried by hand |
| the cursor on the todo tray of a box after a block move | broken: the tray is not lit as part of its box |

## 8. Todo

| State | Item |
|---|---|
| open | cut the 1.3 s between first paint and ready: `json` (protocol.rkt) and `racket/port` (terminal.rkt, live.rkt, home.rkt) load at start |
| open | lower the priority of the background scan so typing never stutters; the scan takes about 8 s on 2 cores |
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
| done | first paint 0.8 s, lazy send, background home scan, gate green with 17 stages |

## 9. Traps

- `PLTCOMPILEDROOTS` set only in the nushell env does not reach the launcher; `aiutd` exports it itself.
- A plain `racket` start on this phone is slow; measure before and after every start-path change.
- The first `edit FILE` call of an older build asked git for facts before painting; the lean path does not.
- The terminal must be given back (echo and line mode on) even when the editor dies; `quick.rkt` does it with a plumber flush and again at exit.
- Never run `git add -A`; the repo holds other projects.

- The timing loop looks for the clear code. After the flicker fix only the first paint of `quick.rkt` sends it, so the loop still works for the first paint; later frames start with ?2026h.

## 10. Report format

Short. Say what changed, then the real output of the last gate or timing run.
No recap of steps.

## 11. Handoff (2026-10-30)

Gate green, 17 stages. The start path is `quick.rkt`, `cli.rkt`, `lean.rkt`. The
next work is the first todo row: the 1.3 s between first paint and ready.

## 11b. Handoff (2026-10-31)

Built since the last handoff: the bar (`bar.rkt`, space b), the tabs (`tabs.rkt`, space t), focus mode (space z), find with fzf (`finder.rkt`, space /), the shared box drawing (`box.rkt`) and the red-only colour in the notation drawing. Next work: the todo tray cursor bug, then the 1.3 s between first paint and ready.

## 11c. Handoff (2026-10-31, later)

The kind layer is gone: the picks are plain keys in visual and the mode line shows visual general, visual navigation or visual selection with the pick (section Pick filter). SPC u (level-up) is still bound and one-way; ask the owner whether it goes.

## 12. Future plans

Ask the owner before starting any of these.

- Tab completion for .aiu: one completion core, in a module loaded on first use (never required by quick.rkt, cli.rkt, lean.rkt, live.rkt or home.rkt). Input is the page text and the point; output is candidates by context: block names at a line start (with a snippet for the start line, the end line and the point between), values after kind:, language: and todo:, tags already used across pages after tags:. Read block names and declarations from the notation engine; do not copy them. If it has no list to read, keep a small table in the editor and make the gate compare it with the notation.
- Completion key: tab is the trigger of the write layer, so use tab tab and leave the layer with escape.
- LSP: a separate stdio server over the same core, answering textDocument/completion, built after the in-editor version.
