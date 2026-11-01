# PLAN: self-testing, self-documenting AIU EDITOR (written 2026-11-01)

Owner decision. Give this file to any AI first. Update it in the same step as any work.

## What the owner wants
1. Built-in commands replace one-off scripts: `aiutd update`, `aiutd test`, `aiutd trace`. Tests run by level, verbose, built in, one per feature.
2. Tests write the docs. Nobody edits the docs by hand. A feature appears in the docs only when its tests pass.
3. Renames: README.md becomes `aiutd-tutorial.aiu` (humans, opened with `aiutd aiutd-tutorial.aiu`). README-AI.md becomes `ai-starting-point.md` (AI). New `todo.aiu` holds every planned feature taken from the READMEs.
4. Each CLI command is documented in the tutorial by the code itself.
5. No more random scripts. Output is pasted back by the owner; replies are prompts only.

## Design
- Feature registry: one file per feature in `editor/src/features/`, each gives: name, keys, commands, docs text (tutorial block), AI notes, tests with a level.
- Levels: 1 new (only what changed since last green), 2 features (all feature tests), 3 everything (features, gate stages, timing). `aiutd test --level N`.
- `aiutd update` = raco make, then tests at the level given (default 2), then regenerate docs, then git commit with explicit paths. Stops at the first red and prints the real failing lines.
- `aiutd docs` writes `aiutd-tutorial.aiu` and `ai-starting-point.md` from the registry and the passing results. Hand-written parts live in `docs/parts/` as small .aiu or .md fragments only for things code cannot know (rules, owner traps).
- `todo.aiu` is generated from the registry entries marked planned plus the fragment `docs/parts/todo-source`. When a feature passes it moves out of todo.
- Headless driver (section 24 of the old README): real key loop, virtual terminal, plain-text screen capture, assertions. Trace (AIU_TRACE) is part of it.

## Steps
| # | Step | State |
|---|---|---|
| 0 | read .aiu syntax, launcher script, gate, how docs are referenced in code and gate | next |
| 1 | todo.aiu from all planned items of both READMEs (sections 8, 10, 12, 13, 14, 15, 22, 23, 24) | open |
| 2 | feature registry + `aiutd update` (compile, gate level, commit) | update.rkt built: compile and gate by level; registry and commit open |
| 3 | trace (AIU_TRACE) in live.rkt | open, first patch refused |
| 4 | headless driver + `aiutd test --level` + first feature tests (move, write, save) | open |
| 5 | `aiutd docs`: generate tutorial.aiu and ai-starting-point.md, then git mv the READMEs and fix references in code and gate | open |
| 6 | tests for cursors, selection, copy, paste, undo | open |
| 7 | marks, bookmarks, completion, rest of todo.aiu, each added with its tests | open |

## Traps (keep)
- Trace patch of 2026-11-01 was REFUSED: anchor `(repaint session viewport)` occurs 6 times in live.rkt, `(define result (act-on session pending))` once. Use the key-loop one only, or edit by line range after reading.
- Nushell: one bash -c, single quotes outside, none inside, nothing after the closing quote. Git with explicit paths only. No backup files. Lazy modules only; nothing on the start path. Nothing runs while the owner types.
- Do not rename the READMEs until step 5: code and gate may refer to them.

## Output rule (owner, 2026-11-01)
Every aiutd command prints: one empty line, a banner, one empty line. The banner is a title block of an .aiu page built in memory and drawn by notation view at the terminal width, like the dashboard. todo.aiu (written by hand once, then generated) holds all planned features. Steps 0 and 1 are done.

Spacing update (owner, 2026-11-01): TWO empty lines above and TWO after the banner and output of every aiutd command, not one. A todo is a paragraph with a todo: line (declaration keyword, not a block type); the todo text is drawn in the tray and the body line above it holds the detail, so generated todos need a real detail line.

Timing rule (owner, 2026-11-01): the banner is printed first AND last. Every step of every command, and every feature test, is timed with the same records, written to ~/.aiu-timings.log (clock, level, step, seconds), and shown next to the run before, with SLOW when a step grew by half and took over 2 s. Tests built later must use the same timing so hard bugs show as slow steps.

Found by the timing log (2026-11-01): raco make per file cost 32 s each (172 s for five), one raco make call with all files costs about 34 s. aiutd update compiles in one call. Never call raco once per file.

Found by aiutd update (2026-11-01): the gate failed in 0.3 s because nu reads the PWD variable and racket current-directory does not set it. capture now sets PWD. Open: raco make takes 37 to 42 s with no change; measure raco alone.

Found by aiutd update (2026-11-01): nu refuses a PWD with a trailing slash; capture strips it. raco make with no change takes 43 s alone (racket start 0.47 s), so the cost is raco checking the dependency tree: investigate how many files and why, then skip raco when nothing is newer than the last build.

Found by aiutd update (2026-11-01): setting PWD from racket did not satisfy nu (trailing slash); every child now runs through sh -c cd DIR && exec, which sets a clean PWD. aiutd update skips raco make when no .rkt under editor/src is newer than ~/.aiu-build-stamp (raco alone costs 30 to 45 s with no change); delete the stamp to force a compile.

Found by aiutd update (2026-11-01): comment-lint was red with 9 debts in undo.rkt (definitions with no comment of their own; a shared comment above a group does not count). Fixed. The gate takes 125 to 148 s: next, time each stage separately and show the slowest three.

Per stage timing (2026-11-01): gate/check.nu prints TIME stage ms for each stage; aiutd update logs them as gate:stage in ~/.aiu-timings.log and shows the three slowest with the previous run. The gate takes about 145 s of a 180 s update, so the slowest stages are the first thing to cut.

Readable report (2026-11-01): aiutd update level 2 lists all 17 gate stages with their seconds; a failing stage is expanded under its line with its own output (first 15 lines). check.nu prints CODE stage n next to TIME. The whole gate output of the last run is in ~/.aiu-last-gate.txt. Tests built later must report the same way: one line per test, failure detail under it.

Levels (2026-11-01): aiutd update --level 1 = compile + quick gate stages (about 20 s), level 2 (default) = + medium stages (about 80 s), level 3 = all 17 stages (about 155 s). check.nu takes --only a,b,c. Slow stages: load-check 33 s, key-check 20 s, kit-check 17 s; they run at level 3 only. Run level 3 before a commit that ends a session.

Test driver (2026-11-01, step 4 started): aiutd test [--level N] runs gate/tests/*.test. A test file: test NAME, level N, file PAGE, keys (key names or single characters), type TEXT, expect screen contains|lacks X, expect file contains|lacks X, expect seconds-under N. The driver copies PAGE to a temporary folder, runs the real editor in a pty (script -qec aiutd FILE), feeds the keys queued at start, waits 4 s, saves the output, then sends escape and q to quit. The screen is the last frame before that escape (frames split at ESC[?2026h, codes stripped, reverse video shown as brackets); the file is read after the quit. Each test is timed and logged as test:NAME. Failed tests print their screen; every screen is saved in ~/.aiu-last-test-NAME.txt. Not yet: per key timing (needs AIU_TRACE), git checks, docs written from passing tests, aiutd update running the tests.

Diagnosis (2026-11-01): a failed test prints its exit code, whether the mid frame exists and the last frame wrapped at 90 columns. The test timeout is 20 s. edit.test also saves with space s.

Key pacing (2026-11-01): the test driver feeds every key as its own chunk, 0.4 s apart, after a 1.5 s lead, because escape followed at once by another byte is read as an Alt chord.

File head (2026-11-01): a failed test prints the first 6 lines of the page file after the run, and no longer prints the screen twice.

Update runs tests (2026-11-01): aiutd update runs the gate stages, then the tests of its level, and shows them in the same report with failure detail inline. Step 4a done.

Trace (2026-11-01, step 4b): live.rkt key-loop calls trace-key! after act-on. It writes to ~/.aiu-trace.log only when AIU_TRACE is set, reads the environment per key and never at load, and adds no require. It times act-on, not the repaint.

Tables (2026-11-01): every report is a boxed table, columns step, stat, secs, prev. Rows come from step-line, any other detail line is a full width box under its row, the total row is last. Written by table-lines in update.rkt, applied inside emit.

Compile timing (2026-11-01): a skipped compile (under 1 s) is not logged, so the next real build is compared with the last real build and no false SLOW shows.

Test selection (2026-11-01): aiutd test --only NAME runs the tests whose file name contains NAME, --repeat N runs them N times, to catch flaky tests. test:edit timed out once in three runs (exit 124), cause not yet seen.

Visible controls (2026-11-01): the file head of a failed test shows control characters as caret letters. test:edit failed 1 in 5 runs with exit 0 and a file head ZZZZs033qtitle start, cause not yet seen.

Run count (2026-11-01): aiutd test prints a line runs N failed M after the report, so repeated runs show how flaky a test is.

Flake hunt (2026-11-01): test:edit fails about 2 in 12 runs, keys land in the page as text (file head ZZZZ s 033q). The test filter matches the file name only (it matched the folder text-editor before). A repeat run stops at the first failing round. The trace logs the first 3 pending keys.

Flake cause (2026-11-01): under load escape and the next key arrived in one read (27 32) and became an Alt chord. The driver now waits 1.5 s after an escape key. The quit escape was the text 033 because the shell stripped the backslash, now sent as a real escape.

Inline trace (2026-11-01): aiutd test runs the editor with AIU_TRACE set and a failed test prints the last 10 trace lines of its own run, so a flaky test explains itself. Open flake: test:edit fails about 1 in 10 runs, the s of space s lands in the page as text, cause not yet seen.

Compact trace (2026-11-01): trace lines in a failed test show the pending keys and the ms only, so no table wrap hides them. Seen in a failed edit run: the file head was ZZZZ033qtitle start, the quit escape is still typed as text.

Tests step 6 (2026-11-01): gate/tests/cursors.test (space c, down adds a cursor on the next line, f writes, Z typed at both) and gate/tests/copy-paste.test (space v selects 3 characters, space y copies, escape, space p pastes). Expectations come from README-AI sections 21 and 23, never tried by hand. Undo test not written yet, it needs saved commits.

Mode per key (2026-11-01): the driver copies the output after every fed key, and a failed test lists the mode line after each key. test:cursors failed with file head ZZZs033qtitle start, cause not yet seen.
