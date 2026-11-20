RULE 0 (THEME): NEVER configure a theme in any program or
config file (no settings.toml, no tv theme, no generated
files, no sync scripts). Every program reads colors ONLY
from my theme engine (themes/active, via theme.rkt in Racket
or a small module that reads the same files in Rust). One
file edit must recolor everything. Splash and tv already do
this (aiu-shell/splashboard/src/theme/aiu.rs and
aiu-shell/television/television/config/themes/aiu.rs).

# START HERE (for any AI)

NEVER LEAVE OPEN HOLES. If you see a hole or a side effect in your own work, close it in the same script. Never write a known hole as a note to him.

This file only explains how to work on this system. It holds no work,
no progress and no next steps. The work is in the todo files and the
plan files. Read ACTIVE WORK below, then go to the files it names.

## ACTIVE WORK
Area: broot first class in the shell.
Plan: todo.aiu, the paragraphs starting todo: broot step.
Read them all, then do the first step left, in order.

When the area changes, replace only the lines inside this block.
Never add steps, results or status here. Never write what was done.

## The person
Shape works on a phone (Termux, proot). He is angry about wasted
tokens. Small moves, small reads. Ask for ALL the code you need in
ONE read. Short answers, answer first, no preamble, ONE code block
per answer, lines under 70 columns. Never make him paste many
times. He may hand you only this file.

## Where and which shell
- Folder: the one this file is in (AIU-ECOSYSTEM). Start every script
  with cd to its absolute path, written as one line. Relative paths
  after that.
- Shell is aiu-shell, a Nushell fork. Wrap bash in bash -c "...".
- aiutd on PATH is /usr/local/bin/aiutd, not the PM launcher.
  It must export AIU_HOT_PATH_BIN and AIU_NOTATION_BIN (prefix
  bins), else a stale hot-path runs and the first draw hangs.

## Rules
- Say what you started only when you start something
  new: one short line. Never recap it in later answers.
- No git, no backup files, no guessed paths, no find over home, no
  comments in code.
- Read first, then patch: grep -c every anchor, abort if the count is
  not the expected one, before every sed. Racket: load check after.
  Rust: the build is the check.
- Never cat big files: tr -d "\033\r" | fold -w 70 | head -c N.
- Output shown in a terminal must wrap to the screen width.
- Racket only: $HOME/opt/racket-full/bin/racket with env
  LANG=C.UTF-8 LC_ALL=C.UTF-8 PLTCOMPILEDROOTS=$HOME/aiu-compiled
- Builds only through the PM, as in AIU-OS/AIU-PM/HOW-TO-USE.md
  (ecosystem live, dev, update, devmode). No cargo or raco by hand.
- BUILD (ecosystem is not on PATH in bash -c). From this folder:
  LANG=C.UTF-8 LC_ALL=C.UTF-8 PLTCOMPILEDROOTS=$HOME/aiu-compiled
  $HOME/opt/racket-full/bin/racket
  "AIU ECOSYSTEM/ecosystem/entry/ecosystem.rkt" live NAME
  > /tmp/eco-live.log 2>&1 ; tail -c 400 /tmp/eco-live.log
  Join the lines. NAME = package. A notation change needs
  aiu-notation, then aiu-editor. Never read HOW-TO-USE.md for it.
- Do not touch the mux z key.
- broot fork: aiu-shell/broot, shallow clone of v1.55.0, no .git. The broot entry in aiu-shell/upstream-version.txt holds url, commit, version. Never run git inside it. My files (managed) change only through the server via aiu-shell/aiu-files; every other file works normally.
- READ ROOT-WARNING.md in this folder before touching file locks, permissions, the server write path or broot. This system has no real root.
- OPEN THE EDITOR IN THE SAME CODE BLOCK, ONLY FOR NOTATION FILES. Open only .aiu files, with aiutd FILE.aiu, after the bash -c block inside the SAME code block, and only when the change touches notation or the editor and a .aiu test page shows it. NEVER open .md, .rkt, .rs, .test or any other file, and never after a read-only step or an edit of a non-notation file. Never a second block. If no test page fits a notation change, make a small one in the same block.
- ALL CHANGES IN TMP FIRST. Every script copies each file it will change to /tmp, edits ONLY the /tmp copies, validates them (anchor counts, racket load, line counts), and only if EVERY step passed does it cp them over the real files, all at the end together. Any failure at any step: delete the tmp copies, touch no real file, print what failed. Never patch a real file in place and restore later: a half-applied change is the worst case. Builds run only after the copy-over, and a failed build restores from the saved originals.
- DOCS PAUSED: never run aiutd docs and never touch AIU EDITOR/
  aiutd-tutorial.aiu until he says so. This overrides every rule
  here that says a capability must show in the tutorial or have
  a recorded test. Now only the book plan and the README matter.
- Every finished step of the book plan updates AIU NOTATION/
  README.aiu in the same script, so the why of every addition
  is always written down.
- When the whole book plan is done, do a final README pass:
  every feature gets an explanation, its why and an example.
  Before it, clarify his goals with him, one short question at
  a time, so no hole and no false claim stays in the README.
- After every finished notation feature, update AIU NOTATION/
  README.aiu in the same script. Now and then refresh the AI
  intro with what the AI can do new. When the database server
  runs, the intro names its commands.
- The product uses local git always (commits, no remote). The rule No git is only for my own work on the code.
- rustup and cargo live in HOME/.cargo/bin, not on PATH in bash -c.
  Default toolchain stable 1.99.0, wasm32-unknown-unknown installed.
- Never write a done line in a todo before he confirms on screen.
  When an item is finished, delete it.
- Keep plan, todo and this file compact: when work is done, delete
  its lines at once. Never leave done work, history or long prose.
  Short lines, easy to scan.
- When you learn a better way to work on this system (a command, a path,
  a rule), write it into this file at once, as a rule. Never a log.
- Every decision and every change is written into the plan or todo
  file at once, so nothing depends on the chat.

- No apostrophe inside a bash -c single-quoted script.
- find -type f skips symlinks: use -L or the path.
- Contracts live in .notation/TYPE/ID.rktd.
- Live notation binary: $HOME/aiu-target/live/aiu-notation/release/notation (a symlink, find -type f misses it). Run it with 2>/dev/null, it prints a long block types line to stderr.
- After a change, end the script by opening the test page: nushell line after the bash -c block, never inside it.


- NEW PAGE: write it with a bash -c heredoc (double-quoted
  delimiter), then in the SAME block run
  /usr/local/bin/aiu-contracts FILE.aiu. It fills every contract
  and answer slot, writes them into the file and prints the open
  questions: id, block type and name, question. No editor is
  needed for contracts. --all also lists the answered ones.
- ANSWER THE CONTRACTS: follow NEW FILE FLOW below, three moves,
  three answers. Never skip the last move: he must see the raw
  file with every answer in place. Answers are short honest facts
  about that block, never filler. The id repeats for every block
  of one kind, so match by block name, never by id alone.
- FIX THE SHELL: it must run every normal TUI with the real terminal. No hard coded list of program names (is_fullscreen_line in command_runner.rs). Detect TUIs at runtime, for example by the alternate screen switch, so nothing is ever registered.

- READ THIS FILE FIRST, every session, before asking for any other
  read. Never guess a path or a command: they are written here.
- WEBSITE DRAWS STRUCTURE: the page never shows terminal text or
  color codes. The server sends blocks as data from the notation
  parser and the page draws them as a real UI. Colors and corners
  come only from /theme.

## Server facts (verified)
- ecosystem-server serve: HTTP door 127.0.0.1:8080, routes /theme,
  /index.db, /cmd (POST), /ws, /file?k=KEY (file blocks as
  JSON). Log: ~/.local/state/aiu-ecosystem/
  server.log
- Website folder: AIU ECOSYSTEM/website (index.html, loader.js,
  lib.rs). Last loaded notation folder: state file notation-root.

## How the PM works (verified, rules only)
- Manifest: ecosystem-manifest/NAME.rktd. Keys: source, build,
  install. Entry code: AIU ECOSYSTEM/ecosystem/entry/ecosystem.rkt
  (live branch, then do-live-racket after it).
- (bin SRC DEST): SRC is read relative to the build target dir.
- Wasm manifest: add --target wasm32-unknown-unknown to the cargo argv and write bin SRC as TARGETDIR/wasm32-unknown-unknown/release/FILE.wasm.
- Wasm extern imports need #[link(wasm_import_module = "env")], else rust-lld fails with undefined symbol.
- ecosystem live NAME runs the manifest cargo argv in the source
  folder with --target-dir swapped for ~/aiu-target/live/NAME.
  Output lands in ~/aiu-target/live/NAME/release/.
- live: a bin SRC under the target dir is read from the live
  target. Any other bin SRC (a launcher script) is read from
  the source folder. Fixed in the pairs line of ecosystem.rkt.
- If any bin file is missing, live prints "binary is missing" and
  the installed version is untouched, even when cargo succeeded.
- Live links go to prefix/NAME/live. prefix = data-home/aiu-pm/prefix.
- live also links every copy-tree into live/ (fixed). aiutd needs
  live/text-editor and the aiu-notation package.
- With XDG_DATA_HOME empty, prefix = ~/.local/share/aiu-pm/prefix.
- A bin SRC read from the source folder must have the exec bit.
  live links it, no copy. aiutd-launcher.sh needed chmod +x.
- The editor compiles notation in by path (Cargo.toml). aiutd reads
  prefix/aiu-notation/current/bin/notation. A notation change needs
  ecosystem live aiu-editor AND ecosystem live aiu-notation.
- Read manifest lines with sed -n Np | fold -w 70. Never cut them.
- Read code with sed -n A,Bp | cut -c1-110. Ask for the next range
  in the same read when the branch is long.

## Tests
- Recorded .test files are never hand-edited: delete and re-record
  with aiutd record-module NAME MODULE-PATH "EXPR".
- Run one test from AIU EDITOR/text-editor:
  aiutd test --level 2 --only FILEBASE
  FILEBASE is the .test file name without .test. The filter matches
  the file name, not the test name. Require "^runs [1-9]" and
  "failed 0".
- Flaky under load: cursors, undo, focus-kinds, pin-view, move,
  copy-paste, block-back.
- Never run the full level 2 or level 3 run unless he asks.
- AIU EDITOR/aiutd-tutorial.aiu is the live test page of NOTATION. It
  is generated by aiutd docs, never hand-edited. Its NOTATION chapters
  are read from the notation files on every run. A new notation
  capability is done only when it shows there.
- aiutd docs must never write this file. Never add that back.
- The editor builds against AIU NOTATION by path (editor/Cargo.toml).
  There is no copy of notation inside the editor. Never make one.

## NEW FILE FLOW

Three moves, one answer each. Verified on a three paragraph page.

MOVE 1, make the page and get the contracts. One bash -c block:
write the file with a heredoc (double-quoted delimiter), then
  /usr/local/bin/aiu-contracts FILE.aiu
It fills every contract and answer slot, writes them into the
file and prints: open: N, then per question the id, block type,
block name and the question. Title needs a kind: line. Refuse if
the file exists. He pastes the output back.

MOVE 2, answer. One bash -c block, /tmp copy only:
- cp FILE to /tmp/x.aiu. Write /tmp/ans.awk: BEGIN holds one
  a["block-name"] = "answer text" per printed question. Rules:
  on contract start or answer start set inx to that word, on
  contract end or answer end clear it. On any other X start push
  a stack, on X end pop. On the first name: line outside a
  contract or answer, store it as the name of the stack top.
  On asked: inside an answer, print the line, then print the
  answer for that stack top name. Count hits and misses into a
  file in the END block.
- Run awk to /tmp/x2.aiu. Abort unless hits equal the number of
  open questions and misses are 0.
- Run aiu-contracts on /tmp/x2.aiu: it must print open: 0, else
  abort. Only then cp /tmp/x2.aiu over FILE, delete the tmp files.
- End the same block with: grep -v "^$" FILE | cut -c1-68

MOVE 3 is that last grep: the raw file with every contract and
answer in place. He pastes it back. Check each answer sits under
the right block, after its asked: line. Done only then.

Open the editor only when he asks to see the page: a nushell
line, aiutd FILE.aiu, never bash -c, it needs the real tty.

- aiu-splash reads SPLASHBOARD_HOME or ~/.splashboard, never ~/.config/splashboard. Theme: ~/.splashboard/settings.toml.
- Rust inside bash -c: no char literals (apostrophe). Insert lines with a sed file: /pat/i TEXT on one line. Rename a fn BEFORE appending a new fn with the old name.
- Splash boxes in the shell show REAL splashboard dashboard output, never self made info.
- aiu-splash dump project|home WIDTH prints a dashboard as plain text, no tty needed. Heredoc with a double-quoted delimiter keeps code literal inside bash -c.

## Server (built in, no variables)
- Website and notation index are ONE server: ecosystem-server
  serve, HTTP 127.0.0.1:8080, socket in
  ~/.local/state/aiu-ecosystem/, log server.log there.
- Autostart: aiu-shell repl.rs runs "ecosystem serve" when the
  shell starts in a terminal. Does nothing if already running.
- Website folder, in order: AIU_WEBSITE_DIR, state file
  website-dir, state file root + "AIU ECOSYSTEM/website",
  then relative "website". Works from any folder.
- Index: every load saves its folder to state file
  notation-root. The server reloads it at start.
- Real index is in "AIU NOTATION/.notation". The .notation in
  the ecosystem root is stale (11-06).
- After a build: ecosystem stop, then ecosystem serve.

## Server commands (built, verified)
- Send: curl -s --data-binary "CMD" http://127.0.0.1:8080/cmd
  or one text message on /ws. Answer is one line.
- Read: ping status load FOLDER reload links FILE backlinks NAME
  broken names git FILE. stop works only from the socket.
- CLI: notation load reload links backlinks broken names go to the
  server over /cmd. notation new FILE (text on stdin) creates a page
  through the server. contracts and fill write through it too. No
  server: reads exit 1, writes go straight to the file.
- Write: write PATH (content on the next lines), delete PATH,
  move FROM (target on the next line). Paths are relative to the
  loaded folder. Each is a local git commit, about 11 s a write.
- A write reindexes that file, writes the body of every live or
  copy link block into its target block file, reindexes that file
  too, then pushes the text changed to every /ws client.
- After ecosystem serve send load with the absolute path of AIU
  NOTATION first, else the answer is no folder loaded and a
  write lands in the wrong folder.
- The editor save (space s) writes the file, then sends the same
  write to the server (notify_server in hot-path.rs). Without a
  server it only writes the file.

## Key w (shell input bar, Visual mode)
- w opens the website (http://127.0.0.1:8080) in the phone
  browser via termux-open-url. Code: open_website in
  aiu-shell-screen command_runner.rs, key arm in input_state.rs.
- Keys already taken in Visual: t h n e s c p a i x o l j k b
  g y Y / space f m M z Z d q. Free: r u v w(now used) and more.
- /theme also has fill, arrow (head, plain, none), grid (on, off).
- Demo pages with links: AIU NOTATION/demo (5 files, ring).
- Block names come from the nearest .notation/blocktypes
  folder, searched upward from the file. The root one
  (.notation/blocktypes) had no link.blocktype, so links
  were never indexed. Copy the type there when a block
  kind is ignored. Default set: AIU NOTATION/notation/
  blocktypes (44 files, root had 43, only link was missing).
- New block types go in both blocktypes folders: the default
  AIU NOTATION/notation/blocktypes and the root .notation/
  blocktypes. layout, card and box were added this way.
- Test layouts: AIU NOTATION/demo/layout-main.aiu and
  layout-inner.aiu. Syntax: layout block with name, card
  blocks (target, place: x y), box blocks (target: layout name).
- Index kind layout-item (index-layouts.rs): fields what
  (card or box), target, place, layout (parent name), line.
- Master view: lib.rs arrange() builds frames and cards from
  layout-item records, draw() paints frames first via rect
  and text. Files in no layout are drawn by plain() below.
- Master view is HTML now: loader.js render() builds a layer
  from the wasm scene (lib.rs scene, scene_ptr: JSON with boxes,
  cards, arrow endpoints). Canvas only paints bg and grid.
- Descriptions: caption declaration in layout, card, box.
  index-layouts.rs writes it, also one record with what=layout.
- Layout width is the window width, not divided by zoom.
- ONE PLACE RULE: every notation asset lives in AIU NOTATION/
  notation/ (blocktypes, types, layouts). Never in demo, never in
  a .notation folder: .notation holds only index.db and the
  root blocktypes copy, and the indexer skips it. Before creating
  or moving files, ask where the same kind already lives.
- Layout files: AIU NOTATION/notation/layouts. Indexed by the
  normal walk, no indexer change.
- Master view settings: AIU NOTATION/notation/layouts/layout-
  settings.aiu, block settings. Keys width height gap stepx stepy
  margin pad head curve. Indexed by index-layouts.rs (what=settings)
  and read by set_cfg in website/lib.rs. Never hard code sizes.
- Master view focus: loader.js foc and applyFocus. Scene link rows
  are [x1,y1,x2,y2,from,to], from and to index into the card list.
- Temp files of a script go in their own folder under /tmp, never
  loose names like /tmp/b2: those can already be folders.
- loader.js tap: phones send a fake mouse click after touchend.
  lt holds the last touch tap time, mouseup skips within 800 ms.
- Master view scope is the scope key in notation/layouts/layout-
  settings.aiu (scope: all shows every file). Read by set_cfg in
  website/lib.rs. Files outside the scope stay in the index.
- Card text padding and font sizes are settings keys (padv padh
  titlesize descsize labelsize). lib.rs style(i) gives them to
  loader.js as sp(i, default).
- Settings TUI: AIU ECOSYSTEM/ecosystem/ecosystem TUI configuration/settings-tui.rkt,
  run from the root with the racket line. check argument tests it.
- Scripts inside bash -c: never a bare double quote or a dollar
  sign in patch text. Write them escaped, or use a placeholder
  like DOLLAR that p.rkt turns into the sign.
- Settings pane: fifth float of the multiplexer, key e in the shell Visual
  mode. Launcher AIU ECOSYSTEM/ecosystem/ecosystem TUI
  configuration/settings-pane.sh reads the root from the state
  file root. New floats: add the name in float-state-shared.rkt,
  keys in split-keys-shared.rkt and pane-split-keys.rkt, command
  and launch in mux.rkt.
- Settings TUI docs: AIU ECOSYSTEM/ecosystem/ecosystem TUI
  configuration/README.md. After any change to the settings TUI
  (keys, rows, float, signal) update it in the same script.
- Settings float: key e in the shell Visual mode sends OSC 7704
  (command_runner.rs toggle_settings). The TUI sends the same
  signal to hide. It is hidden, never killed. Keys: h t n s,
  enter, e. The mux handles it in pane-grid.rkt and mux.rkt.
- Settings float prestart: mux.rkt opens float 4 after the startup fit-panes!, hidden.
- In bash -c with double quotes nushell accepts only backslash-quote and backslash-dollar. Put patterns in single quotes.
- JOB FILE: write each script as a nushell file (raw string, save) to /tmp/aiu/NAME.nu, then run it: ^($nu.current-exe) /tmp/aiu/run.nu NAME. Success deletes it, failure keeps it and prints the error. Fix with a small edit, never rewrite. Use bash only for tools that need it.
