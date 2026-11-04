
## Hard rules (owner, hand written)

- The owner reads on a phone and pays for every round. Say what you saw, not what you hope. Say when you have not seen output. Reply format: one prompt to paste plus short facts.
- Shell is nushell. Every command is ONE bash -c with single quotes outside, nothing after the closing quote, no single quote inside. No 2>&1 outside bash -c. No pipes on long commands. Never plain timeout, use timeout --foreground or none.
- Patch scripts: check every anchor occurs exactly once or refuse and write nothing. One raco make call. On compile failure git checkout the touched files. Commit with explicit paths. Never git add -A, commit -a, reset --hard, clean, stash. No backup files. Do not push. Update plan.md in the same script.
- Every definition has its own comment line above it, every file a header comment (comment-lint). Lazy loading is the main feature: no heavy require in quick.rkt, cli.rkt, lean.rkt, live.rkt. Nothing runs while the owner types.
- Do not edit AIU NOTATION. No .org files, no compiled folders in the tree. Never loop over in-naturals without a bound.
- No one-off scripts for tests or updates: extend aiutd update and aiutd test. No timers or sleeps in the test driver. Every aiutd command prints two empty lines, a banner, a boxed table, the banner, two empty lines.
- A test must end in visual mode: a final escape after k rolls the keep back, and a test that ends inside the undo layer hangs for 15 s.

## Two separate packages

The editor (editor/) and the notation engine (notation/) are two separate packages with two separate binaries. They live in one folder but are never combined into one binary. Later notation gets its own literate mode, like org mode, and the two are sent and shipped separately, never as one package.
