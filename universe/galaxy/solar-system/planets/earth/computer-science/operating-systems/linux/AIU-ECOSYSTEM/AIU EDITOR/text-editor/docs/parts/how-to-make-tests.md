
## How to make tests (never write them by hand)

A test is recorded from a real run, not typed. Run: aiutd record NAME KEYS where KEYS are key names (space, escape, tab, return, up, down, left, right, backspace) or single characters, for example: aiutd record focus-on space z. The command runs the keys in the real editor, compares the screen and the file with a run of no keys, writes gate/tests/NAME.test and editor/features/NAME.feature from what changed, and keeps them only when the new test passes. The keys must end in visual mode, or the run hangs for 15 s. Then run aiutd docs, which writes this tutorial from the passing features. Check with aiutd test --level 2 --only NAME and aiutd update --level 2.

## How to make module tests (never write them by hand)

A module test calls one expression in one module and compares the printed answer. Run: aiutd record-module NAME MODULE-PATH EXPRESSION, for example: aiutd record-module update-table editor/entry/update/update-table.rkt "(first-n (list 1 2 3) 2)". The command runs the expression twice in a fresh racket, refuses an answer that differs between the two runs or cannot be a stable line, writes gate/tests/mod-NAME.test and keeps it only when the new test passes. One source file gets one module test; give the expression as a list of several calls to test more than one function. Check with aiutd test --level 2 --only mod-NAME.
