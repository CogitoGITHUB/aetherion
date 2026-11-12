# START HERE (for any AI)

This file only explains how to work on this system. It holds no work,
no progress and no next steps. The work is in the todo files and the
plan files. Read ACTIVE WORK below, then go to the files it names.

## ACTIVE WORK
Area: AIU NOTATION
Read: AIU NOTATION/todo.aiu, AIU NOTATION/book-plan.aiu
Then: follow the todo and the plan. Decided items start with
"Decided", open items are in the "Holes left" lines.

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

## Rules
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
- Never write a done line in a todo before he confirms on screen.
  When an item is finished, delete it.
- Keep plan, todo and this file compact: when work is done, delete
  its lines at once. Never leave done work, history or long prose.
  Short lines, easy to scan.
- When you learn a better way to work on this system (a command, a path,
  a rule), write it into this file at once, as a rule. Never a log.
- Every decision and every change is written into the plan or todo
  file at once, so nothing depends on the chat.

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
