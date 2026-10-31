AI: READ SECTION 18 AT THE END FIRST. Then section 0.

# AIU EDITOR: guide for AI agents

## 0. START HERE (written 2026-10-31, read this before anything else)

You were given README.md and README-AI.md and nothing else. Do this, in this order, with no extra questions.

### 0.1 Verify first (one read request, narrow, all in one block)

Several patches in the last session were sent without their output being seen. Do not assume they applied. Check each with grep and report the real output:

| Patch | Check |
|---|---|
| history archive (section 14.1) | grep -n archive editor/src/journal/journal.rs and editor/src/join/hot-path.rs; ls the journal folder for .base and .history files after one edit; the hot path needs cargo build (CARGO_TARGET_DIR=/tmp/editor-target cargo build --manifest-path editor/Cargo.toml) |
| space h dashboard key | grep -n home-open editor/src/commands/commands.rkt editor/src/routes/keymaps.rkt editor/src/entry/lean.rkt |
| dashboard page rewrite | grep -n code-block editor/src/dashboard/home.rkt |
| git in tabs and fuller git row | grep -n tab-git-text editor/src/dashboard/tabs.rkt |
| git after first paint, no timer | grep -c paint-ready editor/src/dashboard/box.rkt editor/src/dashboard/bar.rkt editor/src/dashboard/gutter.rkt editor/src/entry/live.rkt |
| autosave | grep -n edit-ops editor/src/join/hot-path.rkt |

Then compile and run the gate ONCE (nu gate/check.nu 2>&1 | tail -8; failing lines start with COMMENT or FAIL). Fix only what the real output shows. Do not run the gate again after every small change: the owner finds that wasteful.

### 0.2 Then ask the owner once

Ask the three questions of section 15.8 in ONE message, and nothing else. Do not start building before the answers.

### 0.3 Then build

Section 15 (undo from git commits), step 1, then step 2, and so on, one script per step. After the undo work the order is: section 13 (marks and bookmarks), the dashboard page (todo text and a git section), git mark per tab file, the todo tray cursor bug, the 1.3 s between first paint and ready.

### 0.4 State and traps that cost the owner the most tokens

- The owner reads on a phone and pays for every round. Ask for ALL reads in one request, narrow, and cut each line with cut -c1-110. Never print whole files. Never run measuring loops nobody asked for.
- Nushell: ONE bash -c with single quotes, NOTHING after the closing quote (no 2>&1, no pipe). Put redirects inside. No single quote anywhere inside, not even in comments or text. The mistake of putting 2>&1 after the closing quote was made four times.
- A Racket regexp-replace with a function needs one argument for the match plus one per capture group. A wrong count crashed a patch.
- Never use string-replace with a short anchor that also matches code you just added. Replace the original first, then add the new text.
- Every patch script: check each anchor occurs exactly once before writing, copy the files to /tmp first, restore them if compile fails, update both READMEs in the same script.
- comment-lint wants a comment above every definition. Never put a helper between a definition and its comment.
- The gate does not feel keypresses. After a change on the paint or start path, ask the owner to hold h or t and say if it is smooth. A slow first key was once a 2 s freeze caused by git competing with the first repaint: found by a logging wrapper in AIU_NOTATION_BIN and a fake git on PATH. Do that before guessing.
- The swap of racket/path and racket/port for machine/small.rkt felt slow to the owner and was reverted. small.rkt exists and nothing requires it.
- The hot path caches the answers of the read ops notation, show and notation-render. Adding notation-view to that cache hung the editor. Do not.
- The journal is cleared on every save (OP_SAVE) because current_text replays it on top of the file. Never skip the clear, or every edit applies twice.
- Git in the project repo only with explicit paths (section 16). Undo commits go on the branch aiu-undo of that repo, built with plumbing and a private index file (section 17).
- Do not edit AIU NOTATION. No .org files, no compiled folders, no backup files in the tree, scratch in /tmp.
- The owner is frustrated by wasted tokens and by guesses. Say what you saw, not what you hope. Say when you have not seen output.

### 0.5 Open owner questions still unanswered

SPC u (level-up) is one-way and still bound: keep or remove. Section 13.9 (three questions about marks). Section 15.8 (three questions about undo).

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

## Git strip

`dashboard/gutter.rkt` keeps the hunks of `git diff -U0` for the open file, asked in a thread (4 s after the first ask, then every 15 s or when the file changes). `dashboard/gutterview.rkt` puts one column at the left of every drawn line of an .aiu page: plus for added, equals for changed, minus for removed, on the lines of each leaf block that a hunk touches (`bv-ranges`, exported by `blockview.rkt`, maps blocks to drawn lines). `repaint-now` in `live.rkt` takes one column off the page width for it. Lines are matched by the saved file, so unsaved edits can shift a mark until the next refresh. A removal between two blocks puts a minus on the first drawn line of the block after the gap (git reports it at the line before the gap), a removal inside a block marks the block equals. A swap of two blocks shows as plus on one block and minus at the gap, because git describes it that way. Only glyphs, no colour.

## Autosave

Every hot path request that changes text (type, delete, delete-at, insert-at) is followed by a save of the same file (`ask-hot`, `join/hot-path.rkt`, `edit-ops`, `save-after`), so git sees the change. `edit-hook` is not called by save-after any more: `leave-write` calls it (section 17), so the git row and strip ask git once after the write layer is left, never while typing. The 4 s wait applies only to the first git ask. The journal is cleared on every save; the history is kept in the history file (section 14).

## Git row and git in the tabs

`git-facts` (`bar.rkt`) answers branch, changed files, ahead, behind, last commit, then staged files, unstaged files, inserted lines and deleted lines (`git diff --shortstat HEAD`). `git-text` shows them in the git row of the bar. The git thread also sets `tab-git-text` (`tabs.rkt`), and `tab-rows` ends every tab bar, at all three levels, with a git section holding that text. Both are filled 4 s after start. Untracked files are still not counted.

## Git starts after the page is shown

No timer. `paint-ready` (`box.rkt`) is set by `live-session` right after the first full paint; `git-refresh-maybe` (bar.rkt) and `gutter-refresh-maybe` (gutter.rkt) do nothing until it is true, and one more repaint is started in a thread so they begin at once. Rule from the owner: once the page is shown and can be worked on, everything else may run in the background. Any older text in this file about waiting 4 s is obsolete.

## Dashboard key

Space h in the visual layer runs `home-open` (`commands.rkt`): it sets `home-request` and returns false, which ends the round of `live-session`; `file-session` (`lean.rkt`) then opens the home screen with `home-session` in the same terminal. A page picked there opens as a normal session. The popup lists it as dashboard in the view group.

## Dashboard page

`home-text` (`home.rkt`) builds the home page: title, a code block with the real keys (1 to 9, space ?, space /, space q), a code block with one page per line (`page-rows d 9`), the work paragraph and the open todos. The old text about space r (scan again) is gone because that key was deleted.

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


## 17. Undo commits on the branch aiu-undo (rebuilt 2026-10-31)

Rule from the owner: nothing runs while typing. A keystroke does the edit and the save and nothing else. Git (the git row and the git strip) and the undo commit run once, when the write layer is left with escape (`leave-write`). Reason: with git calls after every save, typing and deleting lagged; with git switched off it was instant.

Code: `bv-after-write` in `dashboard/blockview.rkt` is called by the leave-write command. It calls `edit-hook` (from `join/hot-path.rkt`, found with dynamic-require, so no new require) which marks the git row and strip old, and it notes the saved file for `dashboard/shadow.rkt` in a thread. `save-after` in `hot-path.rkt` no longer calls `edit-hook`. `shadow.rkt` is loaded on first use and is listed in `compile-deps` of `entry/cli.rkt`. One worker waits 0.5 s after the note, then starts ONE niced sh process for each file (the string `commit-script` in `shadow.rkt`); that sh starts the git programs.

The commits go on the branch `aiu-undo` of the git repository that holds the file. The branch starts empty and shares no history with main, so plain git log on main never shows it. Read it with `git log aiu-undo`, or `git log aiu-undo -- FILE`. The editor never checks it out. Each commit uses plumbing and a private temporary index file in the git folder (read-tree of the branch, hash-object, update-index, write-tree, commit-tree, update-ref), so the real index, HEAD and work tree are never touched. If HEAD is on aiu-undo the commit is skipped and logged. A file outside a git repository is skipped. The message is NAME: +A -D lines. No change, no commit. Errors go to `~/.aiu-undo-error.txt`.

Switch: with AIU_NO_UNDO set in the environment of aiutd the editor makes no undo commits.

Only escape in the write layer triggers it so far. Tab tab, quit while writing and a tab switch do not yet: ask the owner. A git strip refresh now happens only after escape, so marks can be old while writing. Dead code left in hot-path.rkt: `shadow-path` and `shadow-note!` (unused, remove later).

Decisions: branch inside the main repo (a separate shadow repository was tried and deleted), one commit for each write session, history file kept. git push --all would push the branch, so push it only on purpose.

Not built yet: undo and redo keys, the tree view, branches for edits after an undo, the block name in the message, worktrees, pruning.

## 18. READ FIRST: owner rule and real state (2026-10-31 late)

OWNER RULE, repeated in anger: NOTHING runs while he types or deletes. No git, no commit, no refresh, no background work on a keystroke. Save to git, the undo commit, the git row and the git strip run only when he LEAVES the write layer (escape, leave-write). One undo step is one write session, never one letter. Never fix this with a debounce timer: it still runs while typing. Ask before building anything that runs on its own. Do not ask for the gate unless the owner asks: it is slow and he hates it.

Measured: with a fake git on PATH (a git that exits 0) typing was almost instant; with real git it lagged. So the cause is git calls after each save: the git row and git strip (edit-hook) and the undo commit worker.

State of the code. VERIFY WITH GREP, do not trust this text:
- shadow.rkt on disk makes commits on the branch aiu-undo (orphan, plumbing, private index file, never checked out). It works, 4 commits were seen. The disk version may be the one that starts about 11 git processes from Racket. A better version (one niced sh process, 0.5 s wait, AIU_NO_UNDO switch) was written in chat and may NOT be installed.
- hot-path.rkt: the shadow-note! call was taken out of save-after, so no undo commit happens now. But save-after still calls edit-hook, so the git row and strip go stale after EVERY keystroke and ask git again. That is the lag still to remove.
- The last patch sent in chat (leave-write calls bv-after-write in blockview.rkt, which calls edit-hook and shadow-note!; save-after calls (void) instead of edit-hook) may NOT have been run. Check: grep -n bv-after-write editor/src/dashboard/blockview.rkt and grep -n edit-hook editor/src/join/hot-path.rkt.
- Dead code in hot-path.rkt: shadow-path and shadow-note! (unused).
- save-after still SAVES the file after every edit op (section Autosave). The owner wants nothing running while he types: ask him whether the save also moves to leave-write (the journal already holds unsaved edits).
- Trigger planned: escape in the write layer only. Tab tab, quit while writing and tab switch are not covered: ask.

Todo in this order: 1 find out which patch is installed. 2 make save-after do only the edit (and the save if the owner agrees), no edit-hook. 3 leave-write: edit-hook once, plus one undo commit in a thread (the niced sh version). 4 the owner types and deletes and says if it is smooth. 5 only then undo and redo keys (u and r), the tree view, the history file decision, worktrees.

Errors of the undo commit go to ~/.aiu-undo-error.txt. The old folder ~/.aiu-undo (separate shadow repository, dropped) may be deleted.
