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
