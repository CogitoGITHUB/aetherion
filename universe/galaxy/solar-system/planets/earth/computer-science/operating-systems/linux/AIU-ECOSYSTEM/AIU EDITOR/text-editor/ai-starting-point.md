# AIUTD starting point (written by aiutd docs, do not edit by hand)

| feature | keys | test notes |
|---|---|---|
| Select, copy and paste | space v, space y, space p | gate/tests/copy-paste.test, expects the file to contain tittitle start. |
| Several cursors | space c, down, f | gate/tests/cursors.test, expects Z typed at both cursors. |
| Writing and saving | space f, escape, space s | gate/tests/edit.test, keys space f Z Z escape space s, expects the file to contain ZZtitle start. |
| Moving between blocks | t | gate/tests/move.test, keys t t t t, expects the screen to contain Moving between blocks. |
| Undo layer | space u, h, k | gate/tests/undo.test, needs repo git, expects Ytitle start kept and YZtitle start gone. A test must end in visual mode. |
