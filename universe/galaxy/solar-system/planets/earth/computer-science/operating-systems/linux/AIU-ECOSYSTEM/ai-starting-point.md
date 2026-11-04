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
