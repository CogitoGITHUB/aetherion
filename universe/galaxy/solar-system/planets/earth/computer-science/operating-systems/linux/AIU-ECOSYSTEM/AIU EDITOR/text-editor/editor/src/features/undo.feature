name Undo layer
test undo
keys space u, h, k
doc Space u opens the undo layer, h steps back to an older saved version, k keeps it as the file.
ai gate/tests/undo.test, needs repo git, expects Ytitle start kept and YZtitle start gone. A test must end in visual mode.
