# AIU NOTATION

A plain-text format for notes, documents and literate code. Files end in `.aiu`.
Everything in a file sits inside a named block, so a person, a script and an AI read it
the same way, and a checker can say what is wrong and on which line.

It is meant to replace Org, Markdown and LaTeX for the writing its author does. Plain
text stays the source of truth: any editor, `grep` and `git diff` work on a `.aiu` file.
This folder adds a checker and a terminal viewer.

Status as of 2026-10-24: the core blocks (title, paragraph, section, code, comment) work
and were run by hand on the author's phone. The status table below says what else is real.

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
   Blank lines between blocks mean nothing.
2. A block is a line `name start`, its content, and a line `name end`. Each marker is
   alone on its line, starts at column 0, is lowercase, and uses the same name both times.
3. Declarations are lines `keyword: value` straight under the start line. Only registered
   keywords count; any other `word: text` line is ordinary content.
4. A code block's body is opaque: nothing in it opens or closes a block. Only the exact
   line `code end` closes it.
5. Blocks nest. A `section` holds other blocks, and its first block is its `title`.
6. Numbers are computed (1, 1.1, 1.2, 2). Never type them.
7. Nothing is repaired silently. A broken file keeps its exact bytes and the error names
   the line. A good file prints back byte for byte (the round trip).

Registered declaration keywords: `tags`, `kind`, `language`, `style`, `theme`, `color`, `format`,
`font`, `level`, `caption`, `column`, `cell`, `row-id`, `meta`, `todo`. They are hints
about a block. The viewer honors `style:` (bold, dim, italic, underline, several allowed
with spaces) and `color:` (red, green, yellow, blue, magenta, cyan, white, gray).

## The blocks

| Block | Purpose |
|---|---|
| `title` | the file's title (first block of the file) and each section's title (first block of the section); `tags:` goes under its start line |
| `paragraph` | prose |
| `section` | holds a title and more blocks, sections included; the nesting depth is the level |
| `code` | opaque text; `language:` goes under its start line |
| `comment` | a note kept in the text; hidden by the viewer |
| `heading` | the older flat heading with `level:`; being replaced by `section` |
| `table`, `header`, `row` | the Rust parser accepts them, but `check` currently rejects them; do not use yet |

## Coming from Org, Markdown or LaTeX

Org and Markdown guess structure from punctuation, so one stray `*` or `#` changes
meaning. Here every part is named with a word, so the checker can be exact.

| You want | Org | Markdown | LaTeX | `.aiu` |
|---|---|---|---|---|
| file title | `#+TITLE:` | `# Title` | `\title{}` | a `title` block, first in the file |
| tags | `:tag:`, `#+FILETAGS:` | front matter | none | `tags:` under the title's start line |
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

## Build

Needs Rust (cargo) and Racket 9 (CS).

~~~
cd "notation system"
cargo build --manifest-path notation/Cargo.toml
export AIU_NOTATION_BIN="$PWD/notation/target/debug/notation"
~~~

Set `AIU_NOTATION_BIN` in every new shell. Without it, `check` stops with exit code 2 and
says so.

## Commands

Run from the `notation system/` folder. Quote paths: the folder name contains a space. Always set
`LC_ALL=C.UTF-8`, or Racket garbles non-ASCII characters in paths.

| Task | Command |
|---|---|
| Check a page | `LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check FILE` |
| View a page | `LC_ALL=C.UTF-8 racket tools/see/see.rkt FILE` (`--plain`, `--width N`) |
| Plain text render | `$AIU_NOTATION_BIN render FILE` |
| Parse tree | `$AIU_NOTATION_BIN parse FILE` |
| Round trip | `$AIU_NOTATION_BIN roundtrip FILE` |

`check` exits 0 when clean, 1 when it found errors, 2 when it could not run (missing file
or binary). Also present, written by earlier sessions and not run by the author:
`render-rich FILE`, `todos FILE`, and the other commands of `cli.rkt`.

On the author's phone, `racket` is not on PATH; the full path is
`/root/home/shape/opt/racket-full/bin/racket`. `tools/aiu.nu` is an older script; prefer
the commands above.

### The `aiu` command and the picker

`tools/see/aiu` is a Nushell script (needs Nushell and Racket) that wraps the commands
above: `aiu see|open|check|render|parse|roundtrip|pick [FILE|FOLDER]`. With a file it works
on that file. With nothing, or a folder, it opens the [television](https://github.com/alexpasmantier/television)
(`tv`) picker over the `.aiu` pages below it, with the formatted page in a preview pane.

Install once: put it on PATH, for example `ln -s "$PWD/notation system/tools/see/aiu" ~/.local/bin/aiu` (from the repo root)`.
`tv` is optional; without it, pass a file. Settings, all optional:

| Variable | Effect |
|---|---|
| `AIU_RACKET` | path of the Racket binary when `racket` is not on PATH |
| `AIU_EDITOR` (else `EDITOR`) | the editor `aiu open` starts |
| `AIU_PICK_FIRST=1` | skip the picker and take the first page (for scripts) |

How the picker works: the tv channel `tools/see/cable/aiu-pages.toml` lists the pages,
previews them with `tools/see/preview.sh`, and on Enter writes the choice to
`/tmp/aiu-pick`, which `aiu` then reads. The choice goes through a file because tv crashes
("cursor position could not be read") when the shell captures its output with `$(tv ...)`
or `| str trim`.

## Errors

`parser-recovery: the parser recovered from X` just means error X. `column unknown` is
normal; the line number is right.

| Error | Meaning | Fix |
|---|---|---|
| `stray-text` | text outside any block, or loose text directly inside a section | put it in a block |
| `mismatched-end` | an end line does not match the innermost open block | fix the name, or close the inner block first |
| `unclosed-block` | a block was opened and never closed | add its end line |
| `unknown-block-name` | the Rust parser does not know that name | use a name from the blocks table |
| `unknown-element-name` | the Racket table does not know that name | same |
| `missing-title` | the file, or a section, does not start with a title block | start it with `title start` |
| `bad-heading-level` | the `level:` of an old `heading` is not a whole number | write 1, 2, 3 |
| `unknown-file-type` | `kind:` names a type that has no module | write an existing type, or make it (see Making a file type) |
| `block-not-in-type` | the page uses a block its `kind:` does not allow | use an allowed block, or change the kind |

Other findings exist (`tag-names-nothing`, `property-no-value`, `link-no-target`); they
come from earlier sessions and are unverified.

## Making a file type

A file type says which blocks a page may use. A page picks one with `kind:` under its
title's start line, and the checker then holds the page to it. Types live in `types/` at
the top of the repo, one module each; no engine file is edited.

1. Create `types/NAME.rkt`:

~~~
#lang racket/base
;; NAME.rkt -- the file type "NAME": one line saying what it is for.
;; Called by: filetypes.rkt (found by scanning types/).
(require "_base.rkt")
(provide the-type)

;; The NAME type.
(define the-type (file-type "NAME" "one line description" (list "title" "paragraph")))
~~~

   The fields are the name (what a page writes after `kind:`), a one-line description,
   and the allowed block names, or `#f` to allow any block.
2. A type that needs more modules gets a folder instead: `types/NAME/type.rkt` provides
   `the-type`, starts with `(require "../_base.rkt")`, and keeps its other modules beside
   it (see `types/book/`). A name starting with an underscore is ignored, so `_draft.rkt`
   is safe scratch.
3. Try it: write a page with `kind: NAME` and run `check`. A disallowed block gives
   `block-not-in-type`; a name no module defines gives `unknown-file-type`.
4. The loader checks in `notation system/gate/tests/filetypes-test.rkt` already cover
   every type: it loads, and no two types share a name. Add a page check there for
   anything special about the new type.
5. Run the gate from `notation system/`: `nu gate/check.nu`. Then add one line for the
   type to `syntax/file-types.org`.

## Status

| Feature | State | Details |
|---|---|---|
| title, paragraph, section, code, comment | works, run by hand 2026-10-24 | `syntax/GUIDE.org` |
| declarations under a start line | works (tags, language, style checked) | `syntax/properties-and-tags.org` |
| stray text is an error, also inside a section | works, run by hand | `syntax/first-slice-freeze.org` |
| a section must start with a title | works, run by hand | `syntax/structure.org` |
| exact round trip | works, run by hand | |
| terminal viewer `see` | works, run by hand | `tools/see/INDEX.org` |
| `aiu` command and tv picker | works, run by hand 2026-10-25 | `tools/see/INDEX.org` |
| section numbers | the viewer computes them; the checker's own numbering still counts only `heading` | `TODO.org` |
| `heading` with `level:` | parsed; being replaced by `section` | |
| tables | the Rust parser accepts them; the checker's name table does not | `syntax/tables-and-figures.org` |
| literate code, JSON, todos, rich render, editor surface, security rules | written by earlier AI sessions, not verified by the author | `syntax/feature-status.org` |
| inline bold, italic, links | not built | |
| math and graphs | far future | |
| including a block from another file | planned; needs authored ids | `TODO.org` |
| file types: `kind:` under the title, one module per type (book, notes) | works, run by hand 2026-10-25 | `syntax/file-types.org` |
| editor hosting: completion, live errors, hidden end lines | planned, separate project | `EDITOR-HANDOFF.org` |
| kit: MCP server, skill, plugin | planned | `TODO.org` |

Known gaps, found by hand:

- `render` drops a line inside a code block when it looks like a block marker; the file,
  `check` and the round trip are correct, only that printed view is wrong (fix is in
  `strip.rs`).
- The viewer and the checker keep separate declaration-keyword lists.
- The error wording `parser-recovery ... column unknown` is clumsy.
- The viewer's underline under a numbered heading is one character too long.

## For AI agents

Everything an AI needs to use this notation and to add a file type is in this README and `AI-GUIDE.md`. Short version:

- Write a page: blocks only (`title`, `paragraph`, `section`, `code`, `comment`), each as `name start` ... `name end`, nothing outside a block, declarations (`kind:`, `tags:`) directly under a start line. Check it: from `notation system/`, `LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check FILE` with `AIU_NOTATION_BIN` set (see Build).
- Add a file type: copy the template in `types/README.md` to `types/NAME.rkt`, set the name, description and allowed blocks, then run `nu gate/check.nu` from `notation system/`. No engine file is edited.
- Never create backup files, never type section numbers, never use blocks marked not built.

- To write `.aiu` files, read `AI-GUIDE.md` first.
- To work on the package, read `AGENT.md`, `TODO.org` and `HANDOFF.org`.

## Repo map

~~~
README.md          this file
AI-GUIDE.md        what an AI must know to write .aiu files
AGENT.md           rules for an AI working on the package
TODO.org           the one list of what is left
HANDOFF.org        the true state
syntax/            the rules, one file per topic, plus example pages
types/             the file types: one module (or folder) per type, used by kind:
notation system/   all the code; every command in this README runs from here
  notation/        Rust crate (parse, render, roundtrip) and Racket package (check, model);
                   every area has its own INDEX.org
  tools/           see (viewer, aiu command, tv picker channel), aiu.nu (older script)
  gate/            the light gate: checks of the code itself
  plan/            package-tree.org: the register of names
~~~

## Development

- Gate: `gate/check.nu`, run with Nushell. It checks parentheses, names, dependency
  direction, the Rust/Racket split, module loading and comments.
- Register a name in `plan/package-tree.org` before you use it. One file, one job, a
  header comment, and a comment above every definition.
- Commit with explicit relative paths, never `git add -A`. Build output and scratch files
  live in `/tmp` or in the git-ignored `notation/target`.

### Adding a feature

Keep this README short: change rows, never paste details here.

1. Write or extend `syntax/<topic>.org` with the rule and an example.
2. New block name: add it to `BLOCK_NAMES` in `notation/src/parser/parser.rs` and to the
   table in `notation/src/elements/register.rkt`. The two lists must agree.
3. New error: add it to `ErrorKind` in `parser.rs`, and one row to the errors table.
4. Change one row in the status table here and one in `syntax/feature-status.org`.
5. Prove it with one real run and put the output in `syntax/first-run-output.org`.
