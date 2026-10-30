# AIU EDITOR: guide for AI agents

Read this whole file before doing anything. It is the working contract for any
AI that changes this package. It holds the todo list, so one cat of this file is
enough.

## 1. Hard rules

| Rule |
|---|
| Lazy loading is the main feature. Never slow the first paint (section 2). |
| No `.org` files and no `compiled/` folders inside the tree. |
| Compile with `PLTCOMPILEDROOTS="$HOME/aiu-compiled"`. |
| `aiutd` must never create or seed a file from `AIU NOTATION/types/default.aiu`. |
| Never create backup files. Scratch goes in `/tmp`. |
| Give all commands in ONE code block per reply, wrapped as `bash -c` (section 4). |
| Use paths relative to the folder the user is in. |
| Whenever a change needs a README update, put it in the same script, every time. |
| Close every gap in the same script. Ask for all the code needed up front, in one request. |
| Replies are short: the owner reads on a phone. Show real output, never say it works without it. |
| Do not edit `AIU NOTATION`. Read it only. |
| Comment above every definition, header comment on every file. The gate enforces it. |

## 2. Lazy loading contract

Measured on the phone (2 cores): first paint 0.8 s for a file and for the home
screen, down from 2.1 s. Editor ready about 2 s. A quit typed at once quits.

| Stage | Module | Rule |
|---|---|---|
| first paint | `entry/quick.rkt` | `racket/base` only. Draws the file head, turns echo and line mode off so keys queue, gives them back at exit. |
| loader | `entry/cli.rkt` | requires only `quick.rkt`. `compile-deps` submodule builds the rest. Loads `lean.rkt` or `cli-full.rkt` with `dynamic-require`. |
| live edit | `entry/lean.rkt` | on a terminal with the edit verb. Commands, keys, screen, home screen. No send, audit, checkpoint, plugin, mcp. |
| every other verb | `entry/cli-full.rkt` | scripted runs (input not a terminal) and all other verbs. The gate proofs read this one. |
| agent side | `send/send.rkt` | loaded by the stub of the send key on first press; it puts the real command in the table. |
| home screen | `dashboard/home.rkt` | shows the kept scan at once, scans in a thread after the first paint, repaints itself. Does not start the hot path. |

Rules for changes:

- Never add a require for send, audit, checkpoint, plugins, mcp, `json`, `net/url` or `racket/port` to `quick.rkt`, `cli.rkt`, `lean.rkt`, `live.rkt` or `home.rkt` without measuring. A heavy feature loads on first use, the way the send stub does.
- Anything slow after the first paint runs in a thread and repaints itself. Nothing waits for a scan.
- A change to the start path ends with the timing run below, and the first paint must stay under 1 s.

~~~
t() { start=$EPOCHREALTIME; paint=""; buf=""; ( sleep 5; printf " q" ) | timeout 20 script -qec "aiutd $1" /dev/null | while IFS= read -r -n1 -d "" c; do buf+="$c"; case "$buf" in *$(printf "\033[2J")*) if [ -z "$paint" ]; then paint=1; echo "$1 first paint: $(awk "BEGIN{printf \"%.1f\", $EPOCHREALTIME-$start}") s"; fi;; esac; done; }
t editor/README.md; t ""
~~~

Do not time "editor ready" with that loop: it rescans the growing output and
reports a number far too high. Time keys typed at once instead: `printf " q" | script -qec "aiutd FILE" /dev/null`.

## 3. Environment

| Variable | Effect |
|---|---|
| `AIU_ROOT` | folder the home scan starts from; `aiutd` sets it |
| `PLTCOMPILEDROOTS` | where compiled files live; `aiutd` sets it to `~/aiu-compiled`; without it every start recompiles for about 10 s |
| `AIU_HOT_PATH_BIN` | Rust hot path program; default `/tmp/editor-target/debug/hot-path` |
| `AIU_NOTATION_BIN` | notation binary; default under `AIU NOTATION/notation system/notation/target/debug/notation` |
| `LANG`, `LC_ALL` | `C.UTF-8`; the project path holds the letter Ae, and a child under the C locale gets it as question marks |

## 4. Shell compatibility

| Case | Rule |
|---|---|
| `aiutd` | POSIX sh, no bashisms; runs from bash, sh, zsh and nushell |
| owner shell | nushell; Nu syntax from AI has been unreliable, so give bash |
| snippets | wrap as `bash -c` with the whole snippet in single quotes; nushell then needs no `&&` |
| inside the wrapper | no single quote anywhere, in code or in comments |
| heredocs | `<<"EOF"` with double quotes, because single quotes break the wrapper |
| Racket patch scripts | write a script to `/tmp`, run it, delete it; use here strings for raw text |
| gate | `nu gate/check.nu` |
| noise | `raco` prints harmless "registered twice" warnings; filter them with `grep -v` |

## 5. Commands

Run from the `text-editor` folder.

| Task | Command |
|---|---|
| Compile | `PLTCOMPILEDROOTS="$HOME/aiu-compiled" raco make editor/src/entry/cli.rkt` (full path of raco: `/root/home/shape/opt/racket-full/bin/raco`) |
| Gate | `nu gate/check.nu` (17 stages) |
| Open a file | `aiutd FILE` |
| Home screen | `aiutd` |

## 6. Gate

Stages: paren-check, load-check, naming, one-way, security-gate, language-split,
comment-lint, route-check, explorer-check, key-check, notation-check,
dashboard-check, secret-check, kit-check, plugin-check, send-check, git-check.
A stage that checks nothing says NOTHING-TO-CHECK. comment-lint wants a comment
line above every definition.

## 7. Status

| Feature | State |
|---|---|
| quick first screen, keys typed during load kept | works, measured |
| lean live session, lazy send | works, measured |
| home screen drawn by the notation view, background scan, kept scan | works, measured |
| home keys (space r, 1 to 9, space q) by hand | not tried by hand |
| a page picked on the home screen opens as a normal session | not tried by hand |
| commands that need a file on the home screen do nothing | not tried by hand |
| scripted sessions and all other verbs | work through `cli-full.rkt`, gate green |

## 8. Todo

| State | Item |
|---|---|
| open | cut the 1.3 s between first paint and ready: `json` (protocol.rkt) and `racket/port` (terminal.rkt, live.rkt, home.rkt) load at start |
| open | lower the priority of the background scan so typing never stutters; the scan takes about 8 s on 2 cores |
| open | try the home keys by hand: space r, 1 to 9, space q |
| open | try by hand that a page picked on the home screen opens as a normal session |
| open | the quick screen shows an .aiu page as raw text until the editor is ready |
| open | the hot path binary lives in `/tmp`; rebuild it or set `AIU_HOT_PATH_BIN` if `/tmp` is cleared |
| open | the scan limits (800 pages, 8 repositories, 4 folders deep) are fixed in code |
| done | first paint 0.8 s, lazy send, background home scan, gate green with 17 stages |

## 9. Traps

- `PLTCOMPILEDROOTS` set only in the nushell env does not reach the launcher; `aiutd` exports it itself.
- A plain `racket` start on this phone is slow; measure before and after every start-path change.
- The first `edit FILE` call of an older build asked git for facts before painting; the lean path does not.
- The terminal must be given back (echo and line mode on) even when the editor dies; `quick.rkt` does it with a plumber flush and again at exit.
- Never run `git add -A`; the repo holds other projects.

## 10. Report format

Short. Say what changed, then the real output of the last gate or timing run.
No recap of steps.

## 11. Handoff (2026-10-30)

Gate green, 17 stages. The start path is `quick.rkt`, `cli.rkt`, `lean.rkt`. The
next work is the first todo row: the 1.3 s between first paint and ready.
