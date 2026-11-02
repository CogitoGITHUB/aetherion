
## How to make tests (never write them by hand)

A test is recorded from a real run, not typed. Run: aiutd record NAME KEYS where KEYS are key names (space, escape, tab, return, up, down, left, right, backspace) or single characters, for example: aiutd record focus-on space z. The command runs the keys in the real editor, compares the screen and the file with a run of no keys, writes gate/tests/NAME.test and editor/features/NAME.feature from what changed, and keeps them only when the new test passes. The keys must end in visual mode, or the run hangs for 15 s. Then run aiutd docs, which writes this tutorial from the passing features. Check with aiutd test --level 2 --only NAME and aiutd update --level 2.
