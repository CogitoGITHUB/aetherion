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
- Paths are relative to the text-editor folder. No timeouts. Every aiutd record or record-module call ends with < /dev/null.
- Never create backup files.

GIT
- Never git add -A, commit -a, reset --hard, clean, stash or force push.
- Commit with explicit paths (git add -u -- paths, or git add -- path for new files), then git push.
- No Claude or Co-Authored-By lines in commit messages.

CODE RULES
- No comments in code. No .org files. No README files; the plan goes to plan.md only.
- No abstract naming for any function, file or directory. A name says what the thing does and which group it belongs to (editor-tui-bar-state, blockview-command-pin-hide). Never helper, util, misc, common, stuff, data, tmp, base or numbered names.
- Everything is categorised properly, like the editor: one directory per group (tui, commands, entry, machine, devloop, join, notation, gate, tests), each file in the group it belongs to, each notification and test next to its group.
- Append one plan line to plan.md BEFORE the work.
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
- The notation binary is in the AIU NOTATION project own target folder; AIU_NOTATION_BIN overrides it.
- Compile output of Racket goes to ~/aiu-compiled (PLTCOMPILEDROOTS).

SCREEN LAYOUT
- Separate boxes, never merged: tab box (top), title box, page box (own top and bottom rule), mode box (bottom).
- The title box sits above the page box, is fed from live-paint, drawn by bar-plan-of in editor/tui/bar/bar.rkt, hidden by the title pin (key x, pin-hide) and hidden while the cursor is on the title block so it can be edited in the page. The title pin never floats over the page while the title box is shown.
- Recorded screen tests that show the frame must be deleted and re-recorded one by one after a layout change.

OPEN TODO
1. Trailing comments after code and #| |# blocks not stripped yet.
2. Put update, test and gate in ONE directory (check update-table.rkt find-up for gate first).
3. TEST FILE PER SOURCE FILE; sort loose editor folders; notation file names; the rest of todo.aiu.
