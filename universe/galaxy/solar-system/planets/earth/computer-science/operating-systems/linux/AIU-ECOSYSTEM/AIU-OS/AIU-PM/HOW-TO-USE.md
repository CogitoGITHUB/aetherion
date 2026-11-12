# AIU ecosystem: how to use it (the only way)

Everything is built and installed through the PM. Never run cargo, raco or a separate build by hand. Never symlink into /usr/local/bin.

## Commands (run from the ecosystem root)
- ecosystem status: what is installed
- ecosystem live NAME: fast incremental build, runs from the live build
- ecosystem dev NAME: full build through the PM and the server, rolls back on failure
- ecosystem update [--dry]: rebuild only what changed (fingerprints)
- ecosystem apply: apply the whole manifest
- ecosystem serve / stop: start or stop the shared server (aiu-shell starts it by itself)
- ecosystem devmode on|off|toggle|status: dev mode flag, off builds everything changed
- ecosystem devwatch: started by dev mode on, live-builds every installed package whose source changed (log ~/.local/state/aiu-ecosystem/devwatch.log)
- ecosystem mux / edit / editor / pm: multiplexer, editor, package manager

## Keys (aiu-shell screen, visual mode, also inside the multiplexer)
- m: dev mode on or off, off builds everything changed through the PM
- M: build everything changed now
- z: zoxide picker, Z: add this directory to zoxide

## Boxes in the multiplexer
- AIU server box at the top: running, stopped or not installed
- red DEV MODE ACTIVE box next to it while dev mode is on
- the aiu-shell screen shows the same boxes right above its own bar when it runs outside the multiplexer

## Never break
- builds write logs to files, never pipe a build to head
- state lives in ~/.local/state/aiu-ecosystem (dev-mode flag, fingerprints, devmode.log)

## Errors
- failed builds in dev mode write the compile text to ~/.local/state/aiu-ecosystem/dev-errors/NAME.log (a good build deletes it)
- a failed update also includes the last lines of the server build log (~/.local/state/aiu-ecosystem/dev.log)
- ecosystem deverrors: print all of them, ecosystem deverrors clear: wipe them
- the multiplexer dev box shows only the error count

## Launch line (when ecosystem is not on PATH)
Run from the ecosystem root, one command, log to a file:

export LANG=C.UTF-8 LC_ALL=C.UTF-8 PLTCOMPILEDROOTS=$HOME/aiu-compiled
$HOME/opt/racket-full/bin/racket "AIU ECOSYSTEM/ecosystem/entry/ecosystem.rkt" live aiu-shell > /tmp/eco-live.log 2>&1

- Replace "live aiu-shell" with any command from the list above.
- Package name is aiu-shell (it includes aiu-shell-screen), not a crate name.
- Read the result with: tail -c 1200 /tmp/eco-live.log
