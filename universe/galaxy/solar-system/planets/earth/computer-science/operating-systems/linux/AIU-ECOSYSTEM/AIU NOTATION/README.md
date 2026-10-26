# AIU NOTATION

A plain-text format for notes, documents and literate code. Files end in `.aiu`.
Everything in a file sits inside a named block, so a person, a script and an AI read it
the same way, and a checker can say what is wrong and on which line.

It is meant to replace Org, Markdown and LaTeX for the writing its author does. Plain
text stays the source of truth: any editor, `grep` and `git diff` work on a `.aiu` file.
This folder adds a checker, a terminal viewer and a small command, `aiu`.

This README is the only documentation, for people and for AI agents. Humans can read it
top to bottom. An agent should read the sections "Writing pages" and "Working on the
package" before doing anything.

Status as of 2026-10-25: the core blocks (title, paragraph, section, code, comment) and
file types work and were run by hand. The status table near the end says what else is real.

## Quick start

~~~
cd "notation system"
cargo build --manifest-path notation/Cargo.toml
export AIU_NOTATION_BIN="$PWD/notation/target/debug/notation"
aiu check ../types/default.aiu     # check a page
aiu see ../types/default.aiu       # view it formatted
aiu                                # menu of commands (tv), preview of each
aiu update                         # after changing code or file types
aiu list                           # blocks and file types that exist now
aiu new journal today.aiu          # a new page from a type starter, checked
aiu gate                           # run the light gate
~~~

Needs Rust (cargo), Racket 9 (CS) and Nushell. tv (television) is optional: it gives the command menu and the page picker. See "The aiu command" to install `aiu`.

## A page in 20 seconds

~~~
title start
tags: demo notes
My first page
title end

paragraph start
Plain text goes inside a paragraph block.
paragraph end

section start
title start
A section
title end
paragraph start
style: bold
Sections nest, and the first block of a section is its title.
paragraph end
code start
language: racket
(display "hello")
code end
comment start
Comments are blocks too. The viewer hides them.
comment end
section end
~~~

Shown with the viewer: the title big and underlined with its tags below, the section
numbered `1  A section`, the code in a frame, no start or end lines, the comment hidden.

## The rules

1. Everything is inside a block. Text outside any block is an error (`stray-text`).
   Only blank lines may sit between blocks.
2. A block is a line `name start`, its content, and a line `name end`. Each marker is
   alone on its line, starts at column 0, is lowercase, and uses the same name both times.
3. The first block of a file is a `title`. The first block inside a `section` is its
   `title`. Loose text directly inside a section is an error.
4. Declarations are lines `keyword: value` straight under the start line, one per line,
   with nothing between. Only registered keywords count; any other `word: text` line is
   ordinary content.
5. A code block body is opaque: it may contain anything except the exact line `code end`.
6. Numbers are computed (1, 1.1, 1.2, 2). Never type them, not even in titles.
7. Nothing is repaired silently. A broken file keeps its exact bytes and the error names
   the line. A good file prints back byte for byte (the round trip).

## The blocks

Run `aiu list` for the current list, read from the parser, with the file types that accept each block.

| Block | Purpose |
|---|---|
| `title` | one line; the file title (first block of the file) and each section title (first block of the section); `tags:` goes under its start line |
| `paragraph` | prose; a few lines are fine, the viewer joins and wraps them; a blank line inside starts a new paragraph |
| `section` | holds a title first, then paragraph, code, comment or section blocks; the nesting depth is the level |
| `code` | opaque text kept exactly; `language:` goes under its start line |
| `comment` | a note for readers; hidden by the viewer; never put a line `x start` or `x end` inside one |
| `heading` | the older flat heading with `level:`; being replaced by `section`; do not write new ones |
| `table`, `header`, `row` | the Rust parser accepts them, but `check` currently rejects them; do not use yet |

## Declarations

Registered keywords: `tags`, `kind`, `language`, `style`, `theme`, `color`, `format`,
`font`, `level`, `caption`, `column`, `cell`, `row-id`, `meta`, `todo`.

Safe to use today:

- `tags: a b c` on a `title`
- `kind: NAME` on the file `title` (see File types)
- `language: name` on a `code` block
- `style: bold` (or dim, italic, underline; several separated by spaces) on a `paragraph` or `title`
- `color: green` (red, green, yellow, blue, magenta, cyan, white, gray) on a `paragraph` or `title`
- `theme`, `format` and `font` are accepted hints that terminals ignore

The keywords made for tables and todos are not verified. Do not use them.

## File types

A file type says which blocks a page may use. A page picks one with `kind: NAME` under its
title start line, and `check` then rejects any block the type does not allow. No `kind:`
line means no type check.

Run `aiu list` to see the blocks and the file types that exist now. The folder
`types/` at the top of the repo holds one generated starter page per type. Never edit
those by hand; look at them to see what a type allows.

To make a type:

1. Run `aiu newtype NAME`, or create `notation/src/filetypes/types/NAME.rkt` by hand:

~~~
#lang racket/base
;; NAME.rkt -- the file type "NAME": one line saying what it is for.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type)

;; The NAME type.
(define the-type (file-type "NAME" "one line description" (list "title" "paragraph")))
~~~

   The fields are the name (what a page writes after `kind:`), a one-line description,
   and the allowed block names, or `#f` to allow any block. Only list blocks the parser
   knows, from the blocks table above.
2. A type that needs more modules gets a folder instead: `notation/src/filetypes/types/NAME/type.rkt`
   provides `the-type`, starts with `(require "../_base.rkt")`, and keeps its other modules
   beside it (see `notation/src/filetypes/types/book/`). A name starting with an underscore
   is ignored, so `_draft.rkt` is safe scratch.
3. Run `aiu update`. It regenerates `types/NAME.aiu`. View it with `aiu see types/NAME.aiu`.
4. Try it: write a page with `kind: NAME` and run `check`. A disallowed block gives
   `block-not-in-type`; a name no module defines gives `unknown-file-type`.
5. Run the gate. The checks in `gate/tests/filetypes-test.rkt` already cover every type:
   it loads, and no two types share a name. Add a page check there only for something
   special about the new type.

No engine file is edited. `aiu update` never deletes pages, so when you remove a type,
delete its page in `types/` by hand.

## Coming from Org, Markdown or LaTeX

Org and Markdown guess structure from punctuation, so one stray `*` or `#` changes
meaning. Here every part is named with a word, so the checker can be exact.

| You want | Org | Markdown | LaTeX | `.aiu` |
|---|---|---|---|---|
| file title | `#+TITLE:` | `# Title` | `\title{}` | a `title` block, first in the file |
| tags | `:tag:`, `#+FILETAGS:` | front matter | none | `tags:` under the title start line |
| chapter, section | `*` `**` | `#` `##` | `\chapter` `\section` | nested `section` blocks |
| section numbers | exporter | none | automatic | computed, never typed |
| paragraph | plain text | plain text | plain text | a `paragraph` block |
| code | `#+BEGIN_SRC` | triple backticks | `lstlisting` | a `code` block with `language:` |
| comment | `# line` | `<!-- -->` | `%` | a `comment` block |
| bold, italic, links in a sentence | `*b*`, `[[x]]` | `**b**`, `[x](y)` | `\textbf{}`, `\href{}` | not built; block-level `style:` only |
| lists | `- item` | `- item` | `itemize` | not built |
| tables | pipes | pipes | `tabular` | `table` blocks, unverified |
| math | LaTeX fragments | `$..$` | native | not built (far future) |
| include another file | `#+INCLUDE:` | none | `\input` | not built (planned) |

## Commands

Run from the `notation system/` folder. Quote paths: the folder name contains a space.
Always set `LC_ALL=C.UTF-8`, or Racket garbles non-ASCII characters in paths.

| Task | Command |
|---|---|
| Check a page | `LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check FILE` |
| View a page | `LC_ALL=C.UTF-8 racket tools/see/see.rkt FILE` (`--plain`, `--width N`) |
| Plain text render | `$AIU_NOTATION_BIN render FILE` |
| Parse tree | `$AIU_NOTATION_BIN parse FILE` |
| Round trip | `$AIU_NOTATION_BIN roundtrip FILE` |
| Update after local changes | `aiu update` |
| List the blocks and the file types | `aiu list` |
| Run the gate | `aiu gate` |
| Menu of all commands | `aiu` |
| New page from a type | `aiu new TYPE FILE` |
| New file type | `aiu newtype NAME` |
| Regenerate starter pages only | `LC_ALL=C.UTF-8 racket notation/src/filetypes/make-live.rkt` |
| Gate | `nu gate/check.nu` |

`check` exits 0 when clean, 1 when it found errors, 2 when it could not run (missing file
or binary). Set `AIU_NOTATION_BIN` in every new shell; without it `check` stops with exit
code 2 and says so. If `racket` is not on PATH, set `AIU_RACKET`; on the phone of the
author the full path is `/root/home/shape/opt/racket-full/bin/racket`. `tools/aiu.nu` is
an older script; prefer the commands above. Also present, written by earlier sessions and
not run by the author: `render-rich FILE`, `todos FILE`, and the other commands of `cli.rkt`.

## The aiu command

`tools/see/aiu` is a Nushell script (needs Nushell and Racket) that wraps the commands
above: `aiu see|open|check|render|parse|roundtrip|pick [FILE|FOLDER]`, `aiu update` and `aiu list`
(no file). With a file it works on that file. With nothing, or a folder, it opens the
[television](https://github.com/alexpasmantier/television) (`tv`) picker over the `.aiu`
pages below it, with the formatted page in a preview pane. `tv` is optional; without it,
pass a file.

`aiu gate` runs the light gate from any folder, with the right environment.

`aiu` with no command opens a tv menu of the commands. The preview pane shows the
usage and a description of the highlighted one. Enter runs it; `new` then opens a
second list of file types, with the starter page of the highlighted type as preview,
and asks for the file name. The last entry of that list, `new-type`, previews how to
make a type, built live from the code (the type record, the block list of the parser
and the types that exist); Enter asks for a name and runs `aiu newtype`. Every
preview wraps its lines to the width of the terminal (`tools/see/fitwidth.sh`), so
no line runs past the screen; page previews go through `tools/see/preview-fit.sh`.
The channels are in `tools/see/cable/`: `aiu-commands.toml` with its list
`aiu-commands.txt` (one line per command: name;usage;description), `aiu-types.toml`, the three `aiu-list-*.toml`
and `aiu-pages.toml`. The choices go through files in /tmp (aiu-cmd, aiu-type,
aiu-pick), because tv crashes when the shell captures its output. Without tv, `aiu`
prints a plain table. A new command needs a line in `aiu-commands.txt` and a row in
the `aiu-help` table of the script.

`aiu new TYPE FILE` copies the starter page of a type to FILE and runs `check` on it, so a
new page starts valid. `aiu newtype NAME` writes `notation/src/filetypes/types/NAME.rkt`
from the template and runs `aiu update`; then set the description and the allowed blocks
in that file and run `aiu update` again.

`aiu list` prints two tables: the blocks the parser knows, with the file types that accept
each one, and the file types that load, with their allowed blocks (`any` means no
restriction). It reads `BLOCK_NAMES` in `parser.rs` and the real loader, so a new type or
block appears without editing anything.

In a terminal with tv, `aiu list` opens a tv menu instead: first the kind (blocks or
file types), then the entries of that kind, with the details read from the code in the
preview. For a block, the types that allow it and the lines of `parser.rs` and
`register.rkt` that name it. For a type, its definition, its module and its starter
page. The last entry of each list helps you make a new one: `new-type` previews how to
make a type, and Enter asks for a name and runs `aiu newtype`; `new-block` previews the
places a block touches (`BLOCK_NAMES` in `parser.rs`, the table in `register.rkt`, the
exceptions in `gate/register-lint.nu`), and Enter asks for a name, checks it and prints
those places with line numbers, because a block still needs hand edits (see Adding a
feature). The channels are `tools/see/cable/aiu-list-kind.toml`, `aiu-list-blocks.toml`
and `aiu-list-types.toml`; the entries come from `aiu-list.sh`, the details from
`aiu-list-preview.sh` and `tools/see/newblock-guide.sh`, so a new block or type shows
up without editing them. `aiu list --plain`, a pipe, or a missing tv prints the two
tables above. Ctrl-C or Esc in any menu or
prompt cancels quietly, with exit code 0.

`aiu update` brings the local install up to date. It rebuilds the Rust binary when any
`.rs`, `Cargo.toml` or `Cargo.lock` is newer than `notation/target/debug/notation`, and
regenerates `types/*.aiu` when anything under `notation/src/filetypes/` is newer than the
oldest page. It prints one line per step: `built`, `regenerated` or `up to date`. It does
not fetch from upstream yet; the marked comment in `update-package` is where that goes.

Install once, from the repo root: `ln -s "$PWD/notation system/tools/see/aiu" ~/.local/bin/aiu`.

| Variable | Effect |
|---|---|
| `AIU_RACKET` | path of the Racket binary when `racket` is not on PATH |
| `aiutd` (else `AIU_EDITOR`, else `EDITOR`) | the editor `aiu open` starts: the AIU editor first, because it reads a page with the notation engine built in |
| `AIU_PICK_FIRST=1` | skip the picker and take the first page (for scripts) |

How the picker works: the tv channel `tools/see/cable/aiu-pages.toml` lists the pages,
previews them with `tools/see/preview.sh`, and on Enter writes the choice to
`/tmp/aiu-pick`, which `aiu` then reads. The choice goes through a file because tv crashes
("cursor position could not be read") when the shell captures its output with `$(tv ...)`
or `| str trim`.

## Errors

`parser-recovery: the parser recovered from X` just means error X. `column unknown` is
normal; the line number is right. Fix one error at a time from the top; later errors may
disappear. `$AIU_NOTATION_BIN parse FILE` prints the parse tree, and its `error` lines give
the kind, the line and what to do.

| Error | Meaning | Fix |
|---|---|---|
| `stray-text` | text outside any block, or loose text directly inside a section | put it in a block |
| `mismatched-end` | an end line does not match the innermost open block | fix the name, or close the inner block first |
| `unclosed-block` | a block was opened and never closed | add its end line |
| `unknown-block-name` | the Rust parser does not know that name | use a name from the blocks table |
| `unknown-element-name` | the Racket table does not know that name | same |
| `missing-title` | the file, or a section, does not start with a title block | start it with `title start` |
| `bad-heading-level` | the `level:` of an old `heading` is not a whole number | write 1, 2, 3 |
| `unknown-file-type` | `kind:` names a type that has no module | write an existing type, or make it |
| `block-not-in-type` | the page uses a block its `kind:` does not allow | use an allowed block, or change the kind |

Other findings exist (`tag-names-nothing`, `property-no-value`, `link-no-target`); they
come from earlier sessions and are unverified.

## Writing pages (for AI agents)

Use only what this README lists as working. If a feature is not listed, do not use it.
Run `aiu list` first to see the blocks and file types that exist now.

The loop:

1. Write the file using only the blocks above.
2. Run `check`. Fix every error it prints. Run it again until it reports no errors.
3. Report the real output of the last check. Never say a file is valid without it.

Common mistakes:

- text between blocks: put it in a `paragraph` block
- a file or section that does not start with a `title` block
- an end line whose name differs from its start line
- a prose line that is exactly `something start` or `something end`: it is read as a block
  marker. Put such lines inside a `code` block
- numbers typed into section titles
- a `keyword: value` line that is not directly under a start line
- inventing block names

Not built, do not write: bold, italic or link markup inside a paragraph (write plain text);
lists, tables, math, includes of other files; `status:` lines; `heading`, `table`,
`header` and `row` blocks.

Do not: create files outside what the user asked for; edit anything under `notation/`,
`gate/` or `tools/` unless the user asked for it.

## Working on the package (for AI agents)

- Work only inside this project folder. Other projects are read-only. If a parent folder
  has its own rules files, they win over this README.
- Read in small pieces, never whole large files. Reports are short and show real output.
  Nothing is done without real output.
- One file, one job, a header comment, and a comment above every definition. The gate
  enforces this.
- Never create backup files. Build output and scratch files live in `/tmp` or in the
  git-ignored `notation/target`.
- Do not run git unless asked. When asked, commit with explicit relative paths of your own
  files, never `git add -A`, push only if the owner asks, and never force past a lock.
- Quote paths, set `LC_ALL=C.UTF-8`, and wrap shell commands in `bash -c` when the user
  shell is Nushell.
- Do not create or edit `.org` files. This README is the documentation.
- The shortcut `aiu` exists only where the owner installed it. Without it, use the
  commands in the Commands table.

## Status

| Feature | State |
|---|---|
| title, paragraph, section, code, comment | works, run by hand 2026-10-24 |
| declarations under a start line | works (tags, language, style checked) |
| stray text is an error, also inside a section | works, run by hand |
| a section must start with a title | works, run by hand |
| exact round trip | works, run by hand |
| terminal viewer `see` | works, run by hand |
| `aiu` command and tv picker | works, run by hand 2026-10-25 |
| `aiu` with no command: tv menus | works, run by hand 2026-10-25; command list, type list with preview, new-type how-to read from the code |
| gate stage `keywords` | works, run by hand 2026-10-25; the keyword lists of `parser.rs`, `properties.rkt` and `json.rkt` must agree |
| `aiu update` | works, run by hand 2026-10-25; local changes only, no upstream fetch |
| `aiu list` | works, run by hand 2026-10-25; blocks from `parser.rs`, types from the loader; tv menus (blocks or types, details in the preview; new-block and new-type entries) |
| `aiu gate`, `aiu new`, `aiu newtype` | works, run by hand 2026-10-25 |
| section numbers | the viewer computes them; the numbering inside the checker still counts only `heading` |
| `heading` with `level:` | parsed; being replaced by `section` |
| tables | the Rust parser accepts them; the name table of the checker does not |
| literate code, JSON, todos, rich render, editor surface, security rules | written by earlier AI sessions, not verified by the author |
| file types: `kind:` under the title, one module per type | works, run by hand 2026-10-25 |
| inline bold, italic, links | not built |
| math and graphs | far future |
| including a block from another file | planned; needs authored ids |
| editor hosting: completion, live errors, hidden end lines | planned, separate project |
| `aiu update` fetching from upstream | planned; no upstream exists yet |
| kit: MCP server, skill, plugin | planned |

Known gaps, found by hand:

- `render` drops a line inside a code block when it looks like a block marker; the file,
  `check` and the round trip are correct, only that printed view is wrong (fix is in
  `strip.rs`).
- The viewer and the checker keep separate declaration-keyword lists; the gate stage `keywords` fails when they disagree.
- The error wording `parser-recovery ... column unknown` is clumsy.
- The underline of the viewer under a numbered heading is one character too long.

## Repo map

~~~
README.md          this file: the only documentation
types/             one starter .aiu page per file type, generated, never edited
notation system/   all the code; every command in this README runs from here
  notation/        Rust crate (parse, render, roundtrip) and Racket package (check, model)
    src/filetypes/        type loader, make-live.rkt, and types/ (one module per file type)
  tools/           see (viewer, aiu command, tv picker channel), aiu.nu (older script)
  gate/            the light gate: checks of the code itself
~~~

## Development

- Gate: `gate/check.nu`, run with Nushell. It checks parentheses, names, dependency
  direction, the Rust/Racket split, module loading, comments, the file type tests and that the block names of the parser and the register agree, that every page checks clean and prints back exactly, and that the keyword lists agree.
- Keep this README short: change rows, never paste details here.

Adding a feature:

1. New block name: add it to `BLOCK_NAMES` in `notation/src/parser/parser.rs` and to the
   table in `notation/src/elements/register.rkt`. The two lists must agree: the gate stage `register` fails when they differ. The only
   exceptions are `table`, `header` and `row`, listed in `gate/register-lint.nu`.
2. New error: add it to `ErrorKind` in `parser.rs`, and one row to the errors table.
3. Change one row in the status table here.
4. Prove it with one real run of `check` on a page that uses the feature.
5. New declaration keyword: add it to the lists in `parser.rs`, `model/properties.rkt` and `data/json.rkt`. The gate stage `keywords` fails when they differ.
