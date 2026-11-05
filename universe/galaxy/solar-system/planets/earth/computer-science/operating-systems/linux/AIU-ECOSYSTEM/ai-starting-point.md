pane-unit-open gets the shell cwd box value, which is an empty string until the first bars refresh: treat empty as no directory. Test every new pane path with an empty string before building aiutm.
Mux pane layer keys follow the Dvorak direction rule: d n focus left right, h t focus down up, r split right, s split down, c close. Both pane/pane-split-keys.rkt and tui/split/split-keys-shared.rkt of the mux tree must agree; the editor copy of split-keys-shared.rkt still has the old n s h t table.
Mux panes: pane/pane-unit.rkt holds grid, pty and scroll box per pane id; layout tab ids are pane ids; fit-panes! in entry/mux.rkt creates panes lazily from layout-rects and prunes panes that are in no buffer layout; lock order is state-lock then lock; layer pane is entered with space w in pane/pane-keys.rkt, keys n s h t focus, r d split, c close; dead panes are closed through layout-focus-id and layout-close. layout-tree-shared.rkt must stay identical in both trees.
Every command bound in keymaps-shared.rkt needs a (list command group label) entry in tui/bar/bar-menu-shared.rkt of the same tree, or the keys menu shows the raw command name. Finished items are removed from the multiplexer todo.aiu by a regexp over the whole paragraph that must match exactly once.
git index refresh (preload index, 2.5 s) over all 8894 tracked files of the Aetherion repo is the git-facts cost on this f2fs disk: status and diff in tui/bar/bar-git-shared.rkt are limited to the shell folder with -- . so the git row is scoped to the cwd. Whole-repo status is always about 2 to 3 s here.
Running git status, diff and log in parallel only cut git-facts from 6.8 s to 6.1 s in the ecosystem repo: the cost is disk or index work, not call order. Measure df -T, tracked file count and a repeated status before changing git-facts again.
git in the ecosystem repo is slow (status about 3.4 s, diff about 2 s): git-facts in tui/bar/bar-git-shared.rkt starts status, diff and log in parallel threads via git-out-later; never run those calls one after another.
Mux bars take the shell cwd as 8th request field: frame/frame-bars.rkt shell-cwd-of walks /proc children from the pty process (no task children file here) and reads the deepest process cwd; the bars server then sets current-directory and resets last-layer so git refreshes.
Editor page scroll branches on blockview-aiu?: .aiu files move top-line in blockview.rkt, plain files move set-view-top!. Check key names of T H pageup with the keyboard.rkt key-names test before binding new keys in the editor.
Scroll is the same in editor and mux: t h line, T H or pageup pagedown page. Editor commands view-page-up and view-page-down live in tui/blocks/blockview.rkt and are bound in routes/keymaps-shared.rkt. Inside the mux the alternate screen forwards page keys to the editor.
- Lessons: the mux buffer layer is entered with SPC b (pane-keys.rkt route-visual) and its h t n c keys are applied in mux.rkt by apply-buffer-keys! with pane/pane-buffer-keys.rkt, the same way as scroll keys; the layer is also listed in routes/keymaps-shared.rkt for the keys menu.
- Lessons: the bars server request has two more fields, buffer names joined by the unit separator and the current buffer index; the mux keeps buffers-state in mux.rkt and the buffer row sits between project and tabs in tab-rows; the editor tabs-shared.rkt differs from the mux copy, so patch it with its own anchors.
- Lessons: naming is workspace, project, buffer, tab; a buffer holds one layout of tabs, a tab is a tiled window (layout-tab in layout-tree-shared.rkt); the buffer list lives in layout-buffers-shared.rkt, both files identical in editor and multiplexer.
- Lessons: the layout engine is tui/layout/layout-tree-shared.rkt, identical in editor and multiplexer (check with cmp); it is pure, sizes are exact fractions of a strip, new windows take half of the focused one, rectangles carry cut-x and cut-y for windows partly scrolled off screen.
- Lessons: key labels for the mux live in routes/keymaps-shared.rkt (trigger-of, normal-keys, the write layer list); the real key routing is pane/pane-keys.rkt; change both together.
- Rule from Shape: in the mux write layer the key that returns to visual is a a (was h h, which clashed with the h scroll key); pending symbol is a in pane-keys.rkt; the keys menu label still has to follow.
- Rule from Shape: mux scroll keys in visual mode are t up, h down, T and H half page (Dvorak), never arrows; arrows and page keys are only sent to the app on the alternate screen.
- Lessons: mux scrolling lives in pane/pane-scroll-keys.rkt (visual layer only: k j u d, arrows, page keys); on the main screen it moves scroll-offset into the grid history that frame-paint.rkt shows, on the alternate screen it forwards arrow and page keys to the app; entering write mode resets the offset.
- Lessons: the editor copy of bar-lines-server-shared.rkt now refreshes git in a background thread when the layer becomes visual (git-on-layer), same as the mux copy; the two copies still differ in keys bar and tab handling.
- Lessons: box drawing for notation lives in the notation binary (cargo build --offline in AIU NOTATION/notation), not in hot-path; cargo check builds no binary, so always cargo build after a notation change and grep -l a new box string in ~/aiu-cargo-target/debug/* to see which binaries hold it; ls -l on that folder prints errors on this filesystem, use ls -lt only for the head.
- Lessons: notation boxes (AIU NOTATION/notation/rendering/boxview.rs) draw titles as ╭─┤ title ├──╮ and TODO/DONE as ┤ badge ├─╮; the bottom label is ╰─┤ DONE ├──╯ and blockview-boxes.rkt matches it with ╰─┤? ; rebuild whatever links the notation crate after changing it.
- Lessons: titles in the editor menus (bar-menu-shared.rkt) use ╭─┤ title ├; the diagnostic regexes in update-screen.rkt and update-evidence.rkt accept both [╭├]─ and [╭├]─┤ before the mode name.
- Rule from Shape: every text on a border line is drawn as ┤ text ├ (edge-line in float/box-shared.rkt, identical in editor and mux); a title line looks like ╭─┤ git ├───╮.
- Lessons: after writing the last terminal column, erase-to-end-of-line erases that column in xterm-like terminals, which cut the right edge off every bar row in the mux; clear the row with ESC [ 2 K BEFORE writing it, never after (frame-paint.rkt).
- Lessons: the clock sits on the bottom border line of the mode bar as ┤ text ├ (clock-rule-line in bar-clock-shared.rkt, identical in editor and mux); the title line carries no stamp; Shape wants every text on a border line in this ┤ text ├ style next.
- Lessons: the clock on the mode bar title line is clock-stamp in bar-clock-shared.rkt (identical in editor and mux); room is width minus title length minus 9; it drops weekday, day part, seconds, date in that order; bar-rows-plain calls it.
- Lessons: bar stack order in the mux is git, keys menu, workspace, project, tabs, mode bar; the keys rows come from keys-body-rows in tui/bar/bar-rows-shared.rkt and are inserted in bar-stack of bar-lines-server-shared.rkt after the first two tab rows, the mode bar is built with the keys cell removed.
- Lessons: Shane wants the mux bar stack ordered git at the top, then workspace, project, tabs lowest next to the mode bar (sections in tab-rows of tui/tabs/tabs-shared.rkt); tabs are empty unless the bars server sets tab-files and tab-current, it now sets the current shell as the only tab; the project row marks nothing when the server cwd is the ecosystem root itself; the editor copy of tabs-shared is not reordered.
- Lessons: racket decodes argv with the locale, so a child racket started from Shane nushell (no UTF-8 locale) sees question marks for the Ae in AIU-ECOSYSTEM even when the path object is correct; the mux sets LC_ALL to C.utf8 with putenv before starting child processes; always test with env -u LC_ALL -u LANG and check the exit code.
- Lessons: Shane nushell has no UTF-8 locale, so path->string on a path with the Ae letter in AIU-ECOSYSTEM turns it into question marks; pass path objects to subprocess and file functions, never path->string; test with env -u LC_ALL -u LANG to reproduce his shell, not with the exported LC_ALL of the scripts.
- Lessons: aiutm is a real executable built with raco exe from AIU TERMINAL MULTIPLEXER/multiplexer/entry/mux.rkt into ~/opt/racket-full/bin (on PATH), never a nushell def and never exec from a script; Shane wants installed binaries he opens by name; inside an exe find-system-path exec-file is the exe itself, so child racket processes use the name racket; rebuild with raco exe -o after changing mux files; patchers must be idempotent and print which anchor failed.
- Lessons: the bars server answered in 5 s because git-facts ran inside the request; never run git or any process on the request path, the server refreshes git in a background thread only when the layer changes to visual; measure each stage alone before adding timers or caches.
- Lessons: never ask the bars server on the key path; keys only update state and show cached bar rows keyed by layer, pending, pinned and width, a separate thread refreshes the cache every 50 ms on change and every second otherwise; terminal-size is polled every 400 ms not every frame.
- Lessons: menu-pinned in bar-state-shared.rkt keeps the keys menu open until closed; space space in visual toggles it and in every other mode only returns to visual (keys-of in routes/keymaps-shared.rkt, command menu-or-visual); the bars server gets layer, short, width, pending and pinned per request; mux modes are visual (default, i enters write, q quits, space space toggles the menu) and write (every byte goes to the shell, h h sends delete and returns to visual); Shane uses only normal keyboard keys on a phone, never esc ctrl or alt; editor and mux keep copies of tui, routes and commands, patch both.
- Lessons: multiplexer starts with racket entry/mux.rkt in AIU TERMINAL MULTIPLEXER/multiplexer (prefix Ctrl-] then q quits, Ctrl-] twice sends it); the pty comes from openpty through ffi and the shell starts with setsid -c; the grid must answer cursor position queries (CSI 6 n) or nu waits; the pane gets the inner size (cols-2, rows-2 minus bar rows); bars come from bar-lines-server-shared.rkt asked over a pipe; checks are /tmp/mux-check.rkt judged by exit code.
- Lessons: the multiplexer interface is a copy of the editor tui code made with /tmp/interface-closure.rkt (closure of bar.rkt, bar-lines-server-shared.rkt, tabs-shared.rkt, bar-menu-shared.rkt, screen.rkt, terminal.rkt, keyboard.rkt; same relative paths); the old Rust multiplexer is deleted, never mention or reuse it; the new project starts from zero in Racket.
- Lessons: the shared-copy tool is /tmp/share-copy.rkt: it takes the closure of tui/bar/bar-lines-server.rkt, rewrites every require string that resolves into the closure to the -shared name, renames the files and their sibling tests in the editor, and copies them into AIU TERMINAL MULTIPLEXER/multiplexer with the same relative paths; .test module lines resolve against the text-editor folder.
- Rule from Shape: shared editor code is never put in one shared directory; the multiplexer copy keeps the editor category directories and subdirectories, every name clear, categorized and unique; each shared file is renamed with shared at the end of its name in BOTH the editor and the multiplexer, and every require is updated on both sides.
- Lessons: the pane is a screen grid in client/screen_grid/screen_grid_apply.rs fed by the raw field of the holder progress record; cursor moves, clears and wraps are applied, scrolled rows go to history; no crate can be fetched offline
- Lessons: holder --shell works when given by hand; aiumux.nu passed /bin/sh anyway, so check the start call arguments in aiumux.nu and verify the pane program with --op state
- Lessons: when Shape says compile, run aiumux --rebuild --start (builds into the state folder, never in the tree) and read the holder --shell argument from /proc/PID/cmdline
- Lessons: /usr/local/bin/aiumux runs nu in a clean env, so it must pass SHELL itself (SHELL=${SHELL:-/bin/sh} after env); the pane program in --op state must be nu
- Lessons: aiumux kill does not end the holder; end it with kill of the pid in sessions/main/holder.pid, remove holder.sock and holder.pid, then aiumux --start; check the pane program in --op state
- Lessons: aiumux.nu starts the holder with the SHELL env, not /bin/sh; restart with aiumux kill main then aiumux --start after changing it
- Lessons: the shell pane starts in Insert mode (keys go to the shell, prefix key for multiplexer commands); the bar server refreshes git itself every 5 seconds because the client has no repaint callback
- Rule from Shape: no bar drawing in Rust; bar_box only asks bar-lines-server.rkt (tabs, workspace, git, mode all from the editor Racket). Obey literally, delete Rust copies
- Lessons: pane rows must be padded to the box width by visible width (escape_free_width in screen_paint_scroll.rs); his paste cuts lines at 80 columns, so a missing right edge in a paste can be the paste, check widths in code
- Lessons: the multiplexer mode box comes from bar-lines-server.rkt run by client/screen_bar/screen_bar_racket.rs; after any change to a bar rkt file run raco make on bar-lines-server.rkt in the editor-code copy
- Rule from Shape: the multiplexer bars come from the editor Racket code through tui/bar/bar-lines-server.rkt (one request line: layer TAB file TAB width, answer: bar rows then an empty line); both copies always identical
- Rule from Shape: two copies of the editor code stand: AIU EDITOR/text-editor/editor and AIU TERMINAL MULTIPLEXER/terminal-multiplexer/editor-code/editor. Every change to tabs, mode line, bars or any other file in one copy is applied to the other copy in the SAME script, same relative path. End every such script with: diff -rq --exclude=compiled --exclude=target "AIU EDITOR/text-editor/editor" "AIU TERMINAL MULTIPLEXER/terminal-multiplexer/editor-code/editor" and judge by its exit code (must be 0)
- Rule from Shape: COPY the working editor files into the multiplexer (editor-code/editor, same relative paths); never rewrite Racket in Rust, never reference the editor directory
- Rule from Shape: Racket is the only copy of the bars. The multiplexer uses the editor Racket code in AIU EDITOR/text-editor/editor/tui/bar and keeps no Rust copy. Never port Racket to Rust.
- Lessons: never run client --op screen or aiumux inside a diagnostic command with pipes; it takes the terminal raw and garbles the paste. Diagnose with --op state only
- Lessons: the aiumux command is /usr/local/bin/aiumux, outside the tree; after moving tools/ update its path there
- Lessons: client without --op prints one state report and exits, it is not interactive; the aiumux command wraps the real interactive start, check tools/aiumux.nu
- Rule from Shape: commit only, NEVER git push unless he asks; a push can fail with a GitHub 500 and wastes rounds.
- Lessons: before debugging the editor, list the running processes (pgrep -fa entry/cli.rkt and hot-path serve) and kill old ones; a long-running editor keeps its old hot-path and environment, so rebuilds and env fixes never reach it.
- Lessons: hot-path links the notation crate by path, so rebuild hot-path (cargo build --offline --bin hot-path in AIU EDITOR/text-editor/editor) after every notation change; a stale hot-path shows false problems in the page box while notation view is fine.
- Lessons: remove comments with a full-line stripper that tracks quote parity so multi-line strings are untouched; count every comment shape first (full-line, trailing, block), then strip, then cargo check. Editor has trailing and block comments, so it needs its own pass.
- Every time you learn something (a rule from Shape, the cause of a failure, a way that works), add it to this file at the top, in the same script as the work, so the next AI starts with it.
- Lessons: run a split patcher from inside the folder of the file it splits, because a path attribute in a file that is not a mod.rs is relative to that file folder; the new group folders are created there. Never edit a patcher with sed, write it fresh and check the path names it writes (each ends in .rs exactly once). Test bodies go to <name>_test/<name>_test_behavior.rs with mod tests; in the source. Find a test block by its mod tests line, not by counting braces, because strings hold braces. After a split delete the unused glob imports cargo names and check again. When a push is refused, git fetch and git pull --rebase, then push. Never leave compiled or target folders in the tree.

AI STARTING POINT: read this first, then work. The owner should never have to prompt you about how to work here.

PROJECT
AIU EDITOR, folder text-editor, Racket plus Rust. Owner: Shape. He reads on a phone, pays for every round and is furious at wasted rounds. He swears; stay calm, do the next step, no long apologies.

REPLY FORMAT
- One bash -c block plus at most 3 short sentences. No explanations, no questions unless blocked.
- He pastes the last command and its output: start from that. Bundle reads. If the layout of a thing is known, patch it. Cap output with head, tail, cut -c1-110, fold -w 60.
- You cannot run anything on his machine. If you have tools that run in a sandbox, do not call them. Only give him the command.

SHELL
- His shell is nushell. Every command is ONE bash -c with single quotes outside and NO single quote inside. Write Racket quote forms as (quote x). Use quoted heredocs (cat <<"EOF").
- Export LC_ALL=C.utf8 in every command. Ignore starship WARN lines.
- Ecosystem root is AIU-ECOSYSTEM (his shell starts there). The editor project is AIU EDITOR/text-editor: cd into it with the path quoted. Paths in commands are relative to that folder.
- Never create backup files.

GIT
- Never git add -A, commit -a, reset --hard, clean, stash or force push.
- Commit with explicit paths (git add -u -- paths, or git add -- path for new files), then git push.
- No Claude or Co-Authored-By lines in commit messages.

CODE RULES
- No comments in code. No .org files. No README files; open items go to todo.aiu (AIU EDITOR/todo.aiu) only, plan.md is deleted.
- No abstract naming for any function, file or directory. A name says what the thing does and which group it belongs to (editor-tui-bar-state, blockview-command-pin-hide). Never helper, util, misc, common, stuff, data, tmp, base or numbered names.
- Everything is categorised properly, like the editor: one directory per group (tui, commands, entry, machine, devloop, join, notation, gate, tests), each file in the group it belongs to, each notification and test next to its group.
- Patch scripts: a small Racket patcher in /tmp where every anchor must occur exactly once or nothing is written. Then compile with aiutd update --level 1 and load touched modules WITHOUT running them. Never run racket FILE on editor/entry/mcp.rkt.
- Close every hole in the same script; do not leave known gaps or follow-up steps.

TESTS
- Recorded .test files are never hand-edited: delete and re-record (aiutd record NAME KEYS, aiutd record-module NAME MODULE-PATH "EXPR").
- Never run the full level 2 or level 3 run unless he asks. Use aiutd test --level 2 --only NAME with NAME without the mod- prefix. Require grep -q "^runs [1-9]" and "failed 0".
- A failing test must print the exact failing point.
- Flaky under load: test:cursors, undo, focus-kinds, pin-view, move, copy-paste, block-back.
- Gates kept: one-way, language-split, secret-check, security-gate. Delete any gate he names.

BUILD
- Cargo output lives outside the tree in ~/aiu-cargo-target (set in ~/.cargo/config.toml). hot-path-bin defaults to ~/aiu-cargo-target/debug/hot-path; AIU_HOT_PATH_BIN overrides it. No target or compiled folders in the tree.
- The notation engine lives in text-editor/notation, its own crate and binary at ~/aiu-cargo-target/debug/notation (AIU_NOTATION_BIN, set in ~/.config/nushell/env.nu). Notation tests sit beside their source; run them with AIU_ONLY=notation/ aiutd update --level 2. gate/skipped.txt lists files excused from a test.
- Compile output of Racket goes to ~/aiu-compiled (PLTCOMPILEDROOTS).

SCREEN LAYOUT
- Separate boxes, never merged: tab box (top), title box, page box (own top and bottom rule), mode box (bottom).
- The title box sits above the page box, is fed from live-paint, drawn by bar-plan-of in editor/tui/bar/bar.rkt, hidden by the title pin (key x, pin-hide) and hidden while the cursor is on the title block so it can be edited in the page. The title pin never floats over the page while the title box is shown.
- Recorded screen tests that show the frame must be deleted and re-recorded one by one after a layout change.

OPEN TODO
1. Trailing comments after code and #| |# blocks not stripped yet.
2. ONE gate at the ecosystem level covering all projects (projects list with roots and levels, aiutd takes the project from where it runs). Next after the notation tests, then the terminal multiplexer: test it, then make it work.
3. TEST FILE PER SOURCE FILE; sort loose editor folders; notation file names; the rest of todo.aiu.

## Two separate packages

The editor (editor/) and the notation engine (notation/) are two separate packages with two separate binaries. They live in one folder but are never combined into one binary. Later notation gets its own literate mode, like org mode, and the two are sent and shipped separately, never as one package.

- Never compile inside the tree: no compiled/ folder and no target/ folder may exist anywhere under AIU-ECOSYSTEM. Every command that runs Racket exports PLTCOMPILEDROOTS="$HOME/aiu-compiled", every command that runs Cargo exports CARGO_TARGET_DIR="$HOME/aiu-cargo-target". Leave the directories clean: after any run that could have written build output, check that find . -type d ( -name compiled -o -name target ) finds nothing.
