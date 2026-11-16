# START HERE (for any AI)

NEVER LEAVE OPEN HOLES. If you see a hole or a side effect in your own work, close it in the same script. Never write a known hole as a note to him.

This file only explains how to work on this system. It holds no work,
no progress and no next steps. The work is in the todo files and the
plan files. Read ACTIVE WORK below, then go to the files it names.

## ACTIVE WORK
Area: AIU NOTATION
Read: AIU NOTATION/book-plan.aiu, chapter Current work: one
book for everything, first. Not the todo.
Then: follow its order of work A to G. Parked items stay
parked. Decided items start with Decided.

When the area changes, replace only the lines inside this block.
Never add steps, results or status here. Never write what was done.

## The person
Shape works on a phone (Termux, proot). He is angry about wasted
tokens. Small moves, small reads. Ask for ALL the code you need in
ONE read. Short answers, answer first, no preamble, ONE code block
per answer, lines under 70 columns. Never make him paste many
times. He may hand you only this file.

## Where and which shell
- Folder: the one this file is in (AIU-ECOSYSTEM). Start every script
  with cd to its absolute path, written as one line. Relative paths
  after that.
- Shell is aiu-shell, a Nushell fork. Wrap bash in bash -c "...".
- aiutd on PATH is /usr/local/bin/aiutd, not the PM launcher.
  It must export AIU_HOT_PATH_BIN and AIU_NOTATION_BIN (prefix
  bins), else a stale hot-path runs and the first draw hangs.

## Rules
- Say what you started only when you start something
  new: one short line. Never recap it in later answers.
- No git, no backup files, no guessed paths, no find over home, no
  comments in code.
- Read first, then patch: grep -c every anchor, abort if the count is
  not the expected one, before every sed. Racket: load check after.
  Rust: the build is the check.
- Never cat big files: tr -d "\033\r" | fold -w 70 | head -c N.
- Output shown in a terminal must wrap to the screen width.
- Racket only: $HOME/opt/racket-full/bin/racket with env
  LANG=C.UTF-8 LC_ALL=C.UTF-8 PLTCOMPILEDROOTS=$HOME/aiu-compiled
- Builds only through the PM, as in AIU-OS/AIU-PM/HOW-TO-USE.md
  (ecosystem live, dev, update, devmode). No cargo or raco by hand.
- ecosystem is not on PATH in bash -c: run the racket line from
  HOW-TO-USE.md with PLTCOMPILEDROOTS. Read /tmp/eco-live.log.
- Do not touch the mux z key.
- OPEN THE EDITOR IN THE SAME CODE BLOCK, ONLY FOR NOTATION FILES. Open only .aiu files, with aiutd FILE.aiu, after the bash -c block inside the SAME code block, and only when the change touches notation or the editor and a .aiu test page shows it. NEVER open .md, .rkt, .rs, .test or any other file, and never after a read-only step or an edit of a non-notation file. Never a second block. If no test page fits a notation change, make a small one in the same block.
- ALL CHANGES IN TMP FIRST. Every script copies each file it will change to /tmp, edits ONLY the /tmp copies, validates them (anchor counts, racket load, line counts), and only if EVERY step passed does it cp them over the real files, all at the end together. Any failure at any step: delete the tmp copies, touch no real file, print what failed. Never patch a real file in place and restore later: a half-applied change is the worst case. Builds run only after the copy-over, and a failed build restores from the saved originals.
- DOCS PAUSED: never run aiutd docs and never touch AIU EDITOR/
  aiutd-tutorial.aiu until he says so. This overrides every rule
  here that says a capability must show in the tutorial or have
  a recorded test. Now only the book plan and the README matter.
- Every finished step of the book plan updates AIU NOTATION/
  README.aiu in the same script, so the why of every addition
  is always written down.
- When the whole book plan is done, do a final README pass:
  every feature gets an explanation, its why and an example.
  Before it, clarify his goals with him, one short question at
  a time, so no hole and no false claim stays in the README.
- Never write a done line in a todo before he confirms on screen.
  When an item is finished, delete it.
- Keep plan, todo and this file compact: when work is done, delete
  its lines at once. Never leave done work, history or long prose.
  Short lines, easy to scan.
- When you learn a better way to work on this system (a command, a path,
  a rule), write it into this file at once, as a rule. Never a log.
- Every decision and every change is written into the plan or todo
  file at once, so nothing depends on the chat.

- No apostrophe inside a bash -c single-quoted script.
- find -type f skips symlinks: use -L or the path.
- Contracts live in .notation/TYPE/ID.rktd.
- Live notation binary: $HOME/aiu-target/live/aiu-notation/release/notation (a symlink, find -type f misses it). Run it with 2>/dev/null, it prints a long block types line to stderr.
- After a change, end the script by opening the test page: nushell line after the bash -c block, never inside it.


- Make a page and open it in the editor in ONE nushell command: a double-quoted string with kind: in the title | save -f FILE.aiu, then aiutd FILE.aiu. Never bash -c, the editor needs the real tty. Opening adds the contracts.
- FIX THE SHELL: it must run every normal TUI with the real terminal. No hard coded list of program names (is_fullscreen_line in command_runner.rs). Detect TUIs at runtime, for example by the alternate screen switch, so nothing is ever registered.

## How the PM works (verified, rules only)
- Manifest: ecosystem-manifest/NAME.rktd. Keys: source, build,
  install. Entry code: AIU ECOSYSTEM/ecosystem/entry/ecosystem.rkt
  (live branch, then do-live-racket after it).
- (bin SRC DEST): SRC is read relative to the build target dir.
- ecosystem live NAME runs the manifest cargo argv in the source
  folder with --target-dir swapped for ~/aiu-target/live/NAME.
  Output lands in ~/aiu-target/live/NAME/release/.
- live: a bin SRC under the target dir is read from the live
  target. Any other bin SRC (a launcher script) is read from
  the source folder. Fixed in the pairs line of ecosystem.rkt.
- If any bin file is missing, live prints "binary is missing" and
  the installed version is untouched, even when cargo succeeded.
- Live links go to prefix/NAME/live. prefix = data-home/aiu-pm/prefix.
- live also links every copy-tree into live/ (fixed). aiutd needs
  live/text-editor and the aiu-notation package.
- With XDG_DATA_HOME empty, prefix = ~/.local/share/aiu-pm/prefix.
- A bin SRC read from the source folder must have the exec bit.
  live links it, no copy. aiutd-launcher.sh needed chmod +x.
- The editor compiles notation in by path (Cargo.toml). aiutd reads
  prefix/aiu-notation/current/bin/notation. A notation change needs
  ecosystem live aiu-editor AND ecosystem live aiu-notation.
- Read manifest lines with sed -n Np | fold -w 70. Never cut them.
- Read code with sed -n A,Bp | cut -c1-110. Ask for the next range
  in the same read when the branch is long.

## Tests
- Recorded .test files are never hand-edited: delete and re-record
  with aiutd record-module NAME MODULE-PATH "EXPR".
- Run one test from AIU EDITOR/text-editor:
  aiutd test --level 2 --only FILEBASE
  FILEBASE is the .test file name without .test. The filter matches
  the file name, not the test name. Require "^runs [1-9]" and
  "failed 0".
- Flaky under load: cursors, undo, focus-kinds, pin-view, move,
  copy-paste, block-back.
- Never run the full level 2 or level 3 run unless he asks.
- AIU EDITOR/aiutd-tutorial.aiu is the live test page of NOTATION. It
  is generated by aiutd docs, never hand-edited. Its NOTATION chapters
  are read from the notation files on every run. A new notation
  capability is done only when it shows there.
- aiutd docs must never write this file. Never add that back.
- The editor builds against AIU NOTATION by path (editor/Cargo.toml).
  There is no copy of notation inside the editor. Never make one.

## NEW FILE FLOW

Make a .aiu file and open it in the editor. One Nushell command:

"title start\nkind: default\nName\ntitle end\n" | save -f f.aiu
aiutd f.aiu

The title needs a kind: line. Opening runs notation fill and adds the contract rows. Never bash -c for aiutd, it needs the real tty.
- aiu-splash reads SPLASHBOARD_HOME or ~/.splashboard, never ~/.config/splashboard. Theme: ~/.splashboard/settings.toml.
- Rust inside bash -c: no char literals (apostrophe). Insert lines with a sed file: /pat/i TEXT on one line. Rename a fn BEFORE appending a new fn with the old name.
- Splash boxes in the shell show REAL splashboard dashboard output, never self made info.
- aiu-splash dump project|home WIDTH prints a dashboard as plain text, no tty needed. Heredoc with a double-quoted delimiter keeps code literal inside bash -c.
