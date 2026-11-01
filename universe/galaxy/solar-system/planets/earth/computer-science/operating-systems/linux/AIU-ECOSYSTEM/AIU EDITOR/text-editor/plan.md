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

Undo test (2026-11-01): gate/tests/undo.test types Z, saves, opens the undo layer, steps back with h and keeps with k, and expects the file to lose the Z. From README-AI section 20, never tried by hand. Flake note: cursors and edit each failed once under load, 0 of 10 afterwards, to be rechecked at level 3.

Undo test red (2026-11-01): test:undo passed alone once, then failed in the level 2 run (file still has Z, keys u h k were read). The mode per key list now also shows the two lines under the mode line, where the undo panel is drawn. The first pass may have been empty: no positive check yet that the undo layer opened.

Repo directive (2026-11-01): a test file may say repo git, then the driver runs git init in its temporary folder only. undo.rkt answers not in a git repository for a page outside a repo, which is the likely cause of the red undo test (not yet seen on screen). Panel lines in the failure report are capped at 70 characters.

Undo message (2026-11-01): with repo git the undo test still fails, space u leaves the mode at visual general. The mode per key list now shows any undo message found on the screen after each key. Cause not yet seen.

Frame driven driver (2026-11-01, owner: no timers): aiutd test sends one key, waits for the next finished frame (ESC[?2026l), snapshots, sends the next, then q. No pacing sleeps. A 20 s deadline per key only reports a hang. Risk: the git row refresh 4 s after start may count as a frame. Earlier settle patch never applied.

Trace driven wait (2026-11-01): the frame driver failed all 5 tests, keys still arrived batched. The driver now sends the next key only after the editor wrote a new trace line for the previous key AND drew a frame. Risk: background frames (git refresh) may still count. The test must end in visual mode because q alone quits only there.

Frames per key (2026-11-01): the mode list of a failed test shows (frames N), the finished frames in the snapshot after each key, and the undo marker is now undo: with a colon. Seen in live.rkt: the key loop writes the trace line before it repaints, so a background frame between them may be taken as the answer to a key. Not yet seen which keys of test:undo get no frame of their own.

Frames file (2026-11-01): aiutd test writes ~/.aiu-last-test-NAME-frames.txt, the last frame after each key, before the temp folder is deleted. Seen: ~/.aiu-last-test-NAME.txt holds only the mid frame taken after the last key, so it never showed the frame after space u. Snapshots lag one key behind in the mode list; not yet fixed.

Edit test keys (2026-11-01): edit.test ends with escape then space s, as the passing runs did. It was found uncommitted in the working tree and is now committed. Seen: edit 10 of 10 ok and cursors 10 of 10 ok under the frame driver. Open: test:undo, the undo layer did not open after space u in the red runs, cause not yet seen. A test must end in visual mode, an undo-open test that ended inside the undo layer hung the run and needed a restart.

Live output (2026-11-01, owner): the driver prints a live line at every step (send key N, frame after key N, NO FRAME, send q, wait for exit, draining output, saving) so a hang shows its last step on screen. Not yet seen running.

Frames loop fix (2026-11-01): the frames file loop used in-naturals and never ended, which hung every test after commit a27bc726. It now runs over the number of keys. Live lines show seconds since the previous line. Not yet seen running.

Frames block removed (2026-11-01): the hang is after driver returned, the in-naturals diagnosis was wrong. The frames file block is gone and live lines mark each step after the driver. Not yet seen running.

wrap-line fix (2026-11-01): wrap-line looped forever when the width was 0 or less, which hung the report after live line building report. Suspected cause, not seen: term-width answers 0 when no tty (timeout). wrap-line now returns the line whole for width under 1.

Short failure report (2026-11-01): the failure detail no longer prints the last frame dump (lines starting with >) and the mode list shows only the mode and frames per key. Seen: plain timeout caused the hangs, timeout --foreground finished; the wrap-line guess was wrong. Seen: with the frame driver the snapshots are in sync, and space u leaves the mode at visual general. Undo message still not seen.

Todo added (2026-11-01, owner): focus mode colours and a hide level, see todo.aiu section Focus mode. Seen: AIU_NO_UNDO is not set in the owner shell, commit-safe! swallows errors into log-error!, the undo error file was not touched by the last run. Not seen: commit-file! and log-error!.

Repo directive fix (2026-11-01): seen, git rev-parse HEAD exits 128 in a repo with no commit, so commit-script exits 0 silently and undo has no versions. repo git now also makes one initial commit in the temp folder.

Undo test green (2026-11-01): seen, undo.test keys space f Y escape space s space f Z escape space s space u h k, expect file contains Ytitle start, 9.5 s. Causes of the earlier reds: the repo had no commit (fixed in the repo directive), there was no older node before Z, and a final escape after k rolled the keep back. The editor was fine.

Undo race (2026-11-01): seen in ~/.aiu-undo-error.txt: cannot lock ref refs/heads/aiu-undo, reference already exists. The save worker and the synchronous commit of space u both create the branch. commit-safe! now holds a commit lock so only one commit runs at a time. Not yet seen running.

Undo flake (2026-11-01): after the commit lock, undo repeat 3 gave 2 ok 1 FAIL and the error file did not change, so the branch race is not the cause. A failed repo git test now lists the commits of aiu-undo in its temp repo. Not yet seen running.

Undo flake (2026-11-01): after the commit lock, undo repeat 3 gave 2 ok 1 FAIL and the error file did not change, so the branch race is not the cause. A failed repo git test now lists the commits of aiu-undo in its temp repo. Seen: capture answers exit code and output. Not yet seen running.

Undo open fix (2026-11-01): seen in undo.rkt ud-start!: the open committed only when unsaved or the tree was empty, so a save made less than 500 ms before space u had no commit yet (the worker waits) and the newest version was missing. Seen: temp repo had one commit in the red runs. ud-start! now always calls shadow-commit-now!. undo.test keys: Y committed by an open, then Z. Not yet seen running.


Live lines in update (2026-11-01): aiutd update prints a live line before and after the compile, before and after each gate stage (one nu call per stage at levels 1 and 2, one call at level 3) and before and after each test, with seconds since the previous line, on stderr. Written by gate-run in update.rkt. Not yet seen running. Next: run aiutd update --level 2 without a pipe, then gate the driver live lines behind an env variable.


Live lines gated (2026-11-01): seen, aiutd update --level 2 GREEN in 141.3 s with live lines, 5 of 5 tests ok (compile 36.5 s, gate 79.2 s). The per key driver lines now show only with AIU_LIVE set; compile, gate stage, test start and done lines and NO FRAME always show. Not yet seen running. Next: feature registry, aiutd docs, todo.aiu generation, README renames; level 3 and repeat checks for flakes.


Feature registry and aiutd docs (2026-11-01): editor/src/features/NAME.feature, plain lines: name, test, keys, doc (one or more), ai. aiutd docs runs each feature test and writes aiutd-tutorial.aiu and ai-starting-point.md in the text-editor folder from the passing ones. The READMEs are untouched, no code or gate refers to them (grep seen empty). Not yet seen running. Next: run aiutd docs, read both files, open the tutorial with aiutd, then todo.aiu generation and the README renames.


Docs fix (2026-11-01): seen, the generated tutorial said Keys: t next block, move.feature now says keys t. Seen, aiutd docs logged nothing to ~/.aiu-timings.log; it now logs each doc step. Seen: aiutd docs takes 25 s because it runs the 5 tests again. Not seen: whether opening aiutd-tutorial.aiu in the editor is slow. Next: run aiutd docs, commit the two generated files, then todo.aiu generation and README renames.


Temp folder fix (2026-11-01): seen, aiutd docs crashed in run-test: delete-directory cannot delete .git of the temp repo, Directory not empty. Cause not seen, likely a git process still writing. The temp folder is now removed with rm -r -f through remove-tree, which never raises. First compile failed (open-output-nowhere is not loaded in update.rkt), now open-output-string. Not yet seen running.


Docs written (2026-11-01): aiutd docs green, aiutd-tutorial.aiu and ai-starting-point.md committed. Not seen: opening the tutorial in the editor. Next: todo.aiu generation, then the README renames.


Docs parts (2026-11-01): seen, aiutd test --level 2 --repeat 5 gave runs 25 failed 0 (cursors and edit SLOW once each under load, cause not seen). docs/parts/*.md are appended to ai-starting-point.md by aiutd docs; docs/parts/ai-rules.md holds the hard rules. README.md and README-AI.md are untouched and unread for this step. Next: read README.md, move its hand-written parts into docs/parts, then the renames; level 3 not run.


Old docs deleted (2026-11-01, owner request): their todo items were compared with todo.aiu, all were there. Mentions in Cargo.toml and todo.aiu reworded. The completion design and sections 12 to 14 went to docs/parts/plans-from-old-readmes.md. Open owner questions 13.9: 1 are the keys of 13.4 right or should marks have their own layer, 2 local marks by block or exact character position, 3 mark letters at the right edge of the page or only in the list. Hand written human parts (keys, home screen, colours, find, bar, tabs) are gone from the tree, history is in git: port them as feature files with tests. Level 3 not run.


Old docs carried over (2026-11-01, owner): README.md lines 1 to 265 and README-AI.md lines 56 to 333 copied from commit bb3679b2^ into docs/parts/old-human-guide.md and old-ai-notes.md, appended to ai-starting-point.md by aiutd docs. Next: turn the human guide into feature files with tests (home keys, block cursor, bar, tabs, focus, find, colour), then todo.aiu generation, then level 3.


More tests (2026-11-01): write-tab and backspace added from the old key tables, kept only if green: [ write-tab backspace ]. Not covered, screens unknown: bar, tabs, focus, find, home keys, block cursor, move layer. Next: read those screens with a frame dump to write expectations, todo.aiu generation, level 3.


More tests (2026-11-01): focus-hide, focus-back, find-escape from the probe screens, kept only if green: [ focus-back ]. Seen: bar and tabs keys leave mode visual general and q does not quit there (probe hung 17 s), screens unknown, no tests. Next: read the bar and tabs code for what space b and space t do, todo.aiu generation, level 3.


Record (2026-11-01, owner: tests must not be written by hand): aiutd record NAME KEYS runs the keys in the real editor, compares screen and file with a no-keys baseline run and writes the test and feature from the difference, kept only when green. Keys must end in visual mode. focus-back was a weak test and is removed. Seen: bar and tabs keys leave the mode unchanged, find needs escape. Not yet seen running.


Launcher fix (2026-11-01): seen, /usr/local/bin/aiutd has its own verb list and did not know record, so aiutd record opened the editor on a file called record. Verb added there. The tutorial now gets the how-to-make-tests section from docs/parts. Not yet seen running.


Record fix (2026-11-01): seen, aiutd record focus-on wrote nothing (nothing changed). Likely cause, not seen: record-lines dropped every line with box characters. They are now stripped first. Not yet seen running.


Record why (2026-11-01): seen, aiutd record focus-on recorded noisy expectations (wrapped fragments, idle bar text) and went RED without a reason. The report now shows the failure detail of its own run. Suspected, not seen: the baseline last frame is a background frame. Not yet seen running.


Frame summary (2026-11-01): seen, aiutd record focus-on took its expectations from the space popup: space z draws about 5 frames (mode list: 2 after space, 7 after z) and the driver snapshots the first, a half-redrawn one. With AIU_FRAMES set the test run writes ~/aiu-frames-summary.txt, one line per frame. Not yet seen running. Next: pick the settled frame from that summary without timers.


Testing paused (2026-11-01, owner): no more test work until the focus mode colours feature works. Open: the recorder takes frame 2 (popup) but frame 7 is settled (seen in the frames summary); write-tab and backspace are hand written; bar and tabs have no tests. Next: focus mode colours from todo.aiu.


NEXT FEATURE (2026-11-01, owner): focus mode colours. Box the cursor is in: lines, text and title white; every other box grey. Then a focus level that hides boxes outside the highlights. Step 1 narrow read of where the lit box is drawn: grep focus-on, bv-view-overlay, and fn sgr in AIU NOTATION (boxview.rs, view.rs). Step 2 one patch. Testing stays paused until it works.


Focus colours (2026-11-01): first compile failed, focus-colours unbound in bar.rkt (box in commands.rkt not visible). Now space z sets the environment variable AIU_FOCUS_COLOURS and bv-view-overlay reads it: lit box white, rest grey. Not yet seen running. Next: the hide level.


Focus colours test (2026-11-01): aiutd record focus-colours space z was RED, nothing committed. Cause: recorder takes frame 2 (popup) instead of settled frame 7. Fix the recorder next.


Settled frame (2026-11-01): seen, late popup frames of space were counted as the answer to z. wait-frame now waits for the first frame AFTER the key trace line (the editor writes the trace line before it repaints). No timers. Risk: a trace line and its frame read in one chunk would wait until the 20 s deadline. Not yet seen running.


Settle race fix (2026-11-01): seen, wait-frame hung 20 s because the frame was read into acc before the trace line was noticed, so base already counted it. Now the trace line is checked before each chunk is appended. Not yet seen running.


Settle popup fix (2026-11-01): seen, after z the first frame after the trace line was still a late popup frame of space (frames 2 to 6), so record and replay judged different frames. The last key now waits for a frame whose plain screen has no waiting after text. No timers. Not yet seen running.


Settle final-frame fix (2026-11-01): seen, with AIU_FRAMES frames 2 to 7 after space z were popup frames and the popup-free frames 8 and 9 never came within 20 s after z, so the popup wait hung. The judge now reads the last frame of the full output after q. Not seen: whether frame 8 follows q. Open: plain-screen strips colours, so a colour-only feature gives the recorder no diff.


Short output (2026-11-01): owner wants only the important lines in the tables. why-short keeps the cause line. Not yet wired to the table.


Short tables (2026-11-01): owner wants only important lines. Test tables now print keys, FAIL lines and the cause (not exit code 0). Record prints the recorded expects on green, FAIL lines and cause on red. Not yet seen running.


Frame colours (2026-11-01): seen, the focus-colours test judges plain text and cannot see colours. AIU_FRAMES summary now counts grey (90m) and white (97m) codes per frame. Not yet seen running.


Colour expects (2026-11-01): seen, frames after space z carry 15 grey codes, frames before 0. judge now takes the raw last frame and understands expect colour grey|white; the recorder writes it when a colour appears only with the keys. Not yet seen running.


Grey default and focus hide (2026-11-01): owner wants, in normal visual mode, all text grey and the block at the point white, always on. space z focus mode shows only that block, every other line empty. Done in bv-view-overlay. Not seen on a phone.


Centre box (2026-11-01): owner wants the lit box always in the middle of the screen. bv-center replaces bv-follow in bv-view-overlay only. Open: keys to scroll the screen only, with the lit box pinned to the bottom edge when scrolling up and the top edge when scrolling down, and a mode with no lit box. Not seen on a phone.


Scroll keys (2026-11-01): g is view-up and r is view-down in the visual layer. They move the view 3 lines and the lit block is kept on screen (pinned at the bottom edge when scrolling up, at the top edge when scrolling down); moving the block centres it again. Open: a mode that scrolls with no lit block. Not seen running.


No-change cause (2026-11-01): seen, aiutd record scroll-view g g r printed only nothing changed. The record now prints where each key is bound and defined, the screen match and the key trace. Not yet seen running.


Floating box (2026-11-01): owner wants the view to keep scrolling with g and r while the lit block floats on the screen edge. bv-place no longer clamps; bv-view-overlay wraps bv-view-overlay-base and copies the block onto the bottom edge when scrolling up and the top edge when scrolling down. Not seen on a phone.


Pin layer (2026-11-01): space o opens pin mode. Pins are boxes drawn on the top or bottom screen edge once their block scrolls out of the window; the first block is pinned by default. Keys a add, d delete, h t select, u b edge, n s order, x hide, f keep in focus (default hidden in focus). Open: the block kind accessor for a real title pin, a focus level 2 setting, baked tables not regenerated. Not seen running.


Err source (2026-11-01): seen, pin-view replay ended on err-wire-lost from join/live-wire.rkt line 91 and the red table did not show it. A red test or record now prints the err- name on the final screen, its source file, line and 8 lines of context. Not yet seen running. Open: why the wire is lost after the pin layer.


Focus typing and pin level 2 (2026-11-01): seen, typing with i or w in focus mode redrew the whole page, because bv-edit-overlay and bv-text-overlay return before + block + after drawn normally. block-overlay now wraps block-overlay-base and blanks the lines outside the edited block in focus mode, shifting the cursor offset by the bytes removed. The first pin (title) defaults to keep-in-focus. Not seen: bv-text-overlay body, running on a phone.

Todo focus box types (2026-11-01): added a section to todo.aiu. Focus can also show the box types around the lit box. Level 2 can show the title of that box type. The notation system would then need to require a title for every box type. The notation folder is not edited from here. Not built.


Focus write plain page (2026-11-01): seen, space f in focus mode showed the raw file because block-overlay returns #f (plain screen) in the write layer before a block is being edited. The wrapper now draws bv-view-overlay in that case when focus is on. Not seen on a phone.


No space f (2026-11-01): owner wants space f deleted. i (block-text) and w (block-edit) are the only keys that start writing from the visual layer, in focus mode too. write-gate removed. Tests backspace, edit, undo, write-tab and focus-type re-recorded with w. Not seen running.


Lacks substring (2026-11-01): seen, every w re-record was red with file lacks kind: default, because w types into the line and the file then holds QQkind: default, which contains the old text. The recorder now skips a lacks expect when a keyed line still contains the text. Not seen running.


Focus write centre (2026-11-01): w and i in focus mode now centre the edited block like the visual view (bv-focus-top in block-overlay). Line numbers assumed 1-based. Not seen running, not seen on a phone.


Focus write pad (2026-11-01): seen, a block near the page top was not centred in focus write because the first line clamps at 1. bv-focus-pad adds blank lines above it. Not seen running, not seen on a phone.


Focus kinds (2026-11-01): focus mode shows the chain of box types of the lit box on the line above it. Level 2 titles are not built, they need AIU NOTATION. Not seen running, not seen on a phone.


Trace paint (2026-11-01): key-loop now times the repaint and writes a paint line to the trace log when AIU_TRACE is set. Not seen running.


Todo clean (2026-11-01): removed the done todos from todo.aiu: banner, update, test levels, headless driver, trace, recorder settled frame, focus colours, focus hide level, focus box types. Kept the notation title todo, it belongs to AIU NOTATION.


CLI docs (2026-11-01): aiutd docs now writes a Commands of aiutd section (cli-section in update.rkt). The trace line is not checked against the verb. Not seen running.
