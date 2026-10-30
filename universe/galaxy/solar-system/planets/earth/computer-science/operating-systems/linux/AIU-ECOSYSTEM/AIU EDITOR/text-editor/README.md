# AIU EDITOR

A terminal text editor written in Racket with a Rust hot path. It is built so a
file is on the screen in under a second, and everything else loads behind it.

AI agents: read README-AI.md first, not this file.

## 1. Lazy loading: the main feature

The rule is open first, load later. The file is drawn before anything else is
loaded, you can type at once, and the rest of the editor arrives while you work.

| Moment | What happens | Measured on the phone |
|---|---|---|
| first paint | the first lines of the file are drawn, with a mode line that says the editor is loading | 0.8 s (was 2.1 s) |
| while loading | keys you type wait in the terminal and run when the editor is ready; none are lost | a quit typed at once quits |
| ready | the commands, the keys and the real screen | about 2 s |
| first use | the send, audit and checkpoint code loads the first time you press the send key | on demand |
| after the paint | the home screen scans pages, todos and git in a thread and repaints by itself | about 8 s, in the background |
| never at start | the home screen does not start the hot path until you open a page | not started |

Why it is built this way: the phone has 2 cores, and every library loaded at
start costs time before the first paint. `json`, `racket/port` and `net/url`
were the slowest to load. So the first screen comes from a module that needs only
`racket/base`, and everything else is loaded after it or on first use.

## 2. Quick start

~~~
aiutd FILE      open a file
aiutd           open the home screen (no file is opened or created)
~~~

`aiutd` is a small sh script. It sets `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`,
`PLTCOMPILEDROOTS` and `AIU_ROOT`, then starts the editor.

## 3. Shell compatibility

| Shell | How it works |
|---|---|
| bash, sh, zsh | `aiutd` is plain POSIX sh with no bashisms; call it directly |
| nushell | call `aiutd FILE` directly; run bash snippets as `bash -c "..."` |
| scripts and snippets | written for bash; no `&&` is needed in nushell because the whole snippet runs inside `bash -c` |

The gate runs under nushell: `nu gate/check.nu`.

## 4. Requirements

| Tool | Needed | Note |
|---|---|---|
| Racket full | yes | `/root/home/shape/opt/racket-full/bin/racket` |
| Rust hot path binary | yes for files | default `/tmp/editor-target/debug/hot-path`, or `AIU_HOT_PATH_BIN` |
| AIU NOTATION binary | no | draws the home screen and pages as boxes; without it the page text shows as it is |
| git | no | feeds the git rows of the home screen |
| nushell | for the gate | `nu gate/check.nu` |

## 5. Keys

The trigger is space. Nothing needs a modifier key.

| Key | Does |
|---|---|
| space w | write layer (tab is the trigger there) |
| space s | save |
| space q | quit |
| space r | view the page as a reader; on the home screen, scan again |
| space b, k | blocks, check (pages) |
| space n, p, e | next block, previous block, block end |
| space g | send (loads its code on first use) |
| escape | back to the visual layer |
| 1 to 9 | on the home screen, open that page |

## 6. Home screen

`aiutd` with no file opens the home screen. It is an AIU page built in memory by
`editor/src/dashboard/home.rkt` and drawn by the notation view, so it looks like
every other page: a title of kind dashboard, a paragraph of keys and scan age,
a paragraph of pages, a paragraph of work and git, and a comment that holds one
paragraph for each open todo the scan found. Every line is scanned from the
folder named by `AIU_ROOT`.

It shows the last scan at once, kept in `~/.aiu-home-scan.rktd` outside the
project tree, then scans in a thread and paints the result when it lands.
Untracked files are not counted in the git rows, because walking them is slow.
Commands that need a file do nothing on this screen.

## 7. Build and check

~~~
PLTCOMPILEDROOTS="$HOME/aiu-compiled" raco make editor/src/entry/cli.rkt
nu gate/check.nu
~~~

No `compiled/` folder and no backup file may sit inside the tree.

## 8. Todo

| State | Item |
|---|---|
| done | first paint 0.8 s for a file and for the home screen |
| done | the send code loads on first use, and the real command lands in the table |
| done | the home screen scans in the background and repaints by itself |
| done | gate green, 17 stages |
| open | cut the 1.3 s between first paint and ready: `json` and `racket/port` load at start, replace them or load them later |
| open | lower the priority of the background scan, so typing never stutters while it runs |
| open | try the home keys by hand: space r, 1 to 9, space q |
| open | try by hand that a page picked on the home screen opens as a normal session |
| open | the quick screen shows an .aiu page as raw text until the editor is ready |
| open | the hot path binary lives in `/tmp`; rebuild it or set `AIU_HOT_PATH_BIN` if `/tmp` is cleared |
| open | the scan limits (800 pages, 8 repositories, 4 folders deep) are fixed in code |

## 9. Repo map

| Path | Holds |
|---|---|
| `README.md` | this guide |
| `README-AI.md` | guide for AI agents |
| `editor/src/entry/` | `quick.rkt` first screen, `cli.rkt` loader, `lean.rkt` file and home session, `cli-full.rkt` every other verb, `live.rkt` the live loop |
| `editor/src/dashboard/` | the home screen and the explorer |
| `editor/src/join/` | the seam to the Rust hot path |
| `editor/src/commands/` | the command table |
| `gate/` | the light gate |
