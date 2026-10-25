# AIU NOTATION

A plain-text format for notes, documents and literate code. Files end in `.aiu`.
Everything in a file sits inside a named block, so a person, a script and an AI read it
the same way, and a checker can say what is wrong and on which line.

It is meant to replace Org, Markdown and LaTeX for the writing its author does. Plain
text stays the source of truth: any editor, `grep` and `git diff` work on a `.aiu` file.
This folder adds a checker and a terminal viewer.

Status as of 2026-10-25: the core blocks (title, paragraph, section, code, comment) and
file types work and were run by hand. The status table below says what else is real.

This README is the only documentation. An AI agent needs nothing else to write `.aiu`
pages or to work on the package.

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
4. A code block body is opaque: nothing in it opens or closes a block. Only the exact
   line `code end` closes it.
5. Blocks nest. A `section` holds other blocks, and its first block is its `title`.
6. Numbers are computed (1, 1.1, 1.2, 2). Never type them.
7. Nothing is repaired silently. A broken file keeps its exact bytes and the error names
   the line. A good file prints back byte for byte (the round trip).

Registered declaration keywords: `tags`, `kind`, `language`, `style`, `theme`, `color`,
`format`, `font`, `level`, `caption`, `column`, `cell`, `row-id`, `meta`, `todo`. They are
hints about a block. The viewer honors `style:` (bold, dim, italic, underline, several
allowed with spaces) and `color:` (red, green, yellow, blue, magenta, cyan, white, gray).

## The blocks

| Block | Purpose |
|---|---|
| `title` | the file title (first block of the file) and each section title (first block of the section); `tags:` goes under its start line |
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

Run from the `notation system/` folder. Quote paths: the folder name contains a space.
Always set `LC_ALL=C.UTF-8`, or Racket garbles non-ASCII characters in paths.

| Task | Command |
|---|---|
| Check a page | `LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check FILE` |
| View a page | `LC_ALL=C.UTF-8 racket tools/see/see.rkt FILE` (`--plain`, `--width N`) |
| Plain text render | `$AIU_NOTATION_BIN render FILE` |
| Parse tree | `$AIU_NOTATION_BIN parse FILE` |
| Round trip | `$AIU_NOTATION_BIN roundtrip FILE` |
| Regenerate starter pages | `LC_ALL=C.UTF-8 racket notation/src/filetypes/make-live.rkt` |
| Update after local changes | `aiu update` |
| Gate | `nu gate/check.nu` |

`check` exits 0 when clean, 1 when it found errors, 2 when it could not run (missing file
or binary). Also present, written by earlier sessions and not run by the author:
`render-rich FILE`, `todos FILE`, and the other commands of `cli.rkt`.

On the author's phone, `racket` is not on PATH; the full path is
`/root/home/shape/opt/racket-full/bin/racket`. `tools/aiu.nu` is an older script; prefer
the commands above.

### The `aiu` command and the picker

`tools/see/aiu` is a Nushell script (needs Nushell and Racket) that wraps the commands
above: `aiu see|open|check|render|parse|roundtrip|pick [FILE|FOLDER]`, and `aiu update` (no file). With a file it works
on that file. With nothing, or a folder, it opens the [television](https://github.com/alexpasmantier/television)
(`tv`) picker over the `.aiu` pages below it, with the formatted page in a preview pane.

`aiu update` brings the local install up to date. It rebuilds the Rust binary when any
`.rs`, `Cargo.toml` or `Cargo.lock` is newer than `notation/target/debug/notation`, and
regenerates `types/*.aiu` when anything under `notation/src/filetypes/` is newer than the
oldest page. It prints one line per step: `built`, `regenerated` or `up to date`. It does
not fetch from upstream yet. It never deletes pages, so remove the page of a deleted type
by hand.

Install once, from the repo root: `ln -s "$PWD/notation system/tools/see/aiu" ~/.local/bin/aiu`.
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
title start line, and the checker then holds the page to it. Types live in
`notation/src/filetypes/types/`, one module each. The loader scans that folder, so no
engine file is edited.

1. Create `notation/src/filetypes/types/NAME.rkt`:

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
   and the allowed block names, or `#f` to allow any block.
2. A type that needs more modules gets a folder instead: `notation/src/filetypes/types/NAME/type.rkt`
   provides `the-type`, starts with `(require "../_base.rkt")`, and keeps its other modules
   beside it (see `notation/src/filetypes/types/book/`). A name starting with an underscore
   is ignored, so `_draft.rkt` is safe scratch.
3. Try it: write a page with `kind: NAME` and run `check`. A disallowed block gives
   `block-not-in-type`; a name no module defines gives `unknown-file-type`.
4. The checks in `gate/tests/filetypes-test.rkt` already cover every type: it loads, and
   no two types share a name. Add a page check there for anything special about the new type.
5. Run `aiu update`, which regenerates the starter pages, then run the gate.

`types/` at the top of the repo holds one generated starter `.aiu` page per type. Never
edit them by hand.

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
| `aiu update` | works, run by hand 2026-10-25; local changes only, no upstream fetch |
| section numbers | the viewer computes them; the checker's own numbering still counts only `heading` |
| `heading` with `level:` | parsed; being replaced by `section` |
| tables | the Rust parser accepts them; the checker's name table does not |
| literate code, JSON, todos, rich render, editor surface, security rules | written by earlier AI sessions, not verified by the author |
| file types: `kind:` under the title, one module per type | works, run by hand 2026-10-25 |
| inline bold, italic, links | not built |
| math and graphs | far future |
| including a block from another file | planned; needs authored ids |
| editor hosting: completion, live errors, hidden end lines | planned, separate project |
| kit: MCP server, skill, plugin | planned |

Known gaps, found by hand:

- `render` drops a line inside a code block when it looks like a block marker; the file,
  `check` and the round trip are correct, only that printed view is wrong (fix is in
  `strip.rs`).
- The viewer and the checker keep separate declaration-keyword lists.
- The error wording `parser-recovery ... column unknown` is clumsy.
- The viewer's underline under a numbered heading is one character too long.

## For AI agents

Writing a page:

- Use blocks only (`title`, `paragraph`, `section`, `code`, `comment`), each as
  `name start` ... `name end`, nothing outside a block.
- Put declarations (`kind:`, `tags:`) directly under a start line.
- Never type section numbers, never use blocks marked not built.
- Check it with `check` (see Commands), with `AIU_NOTATION_BIN` set (see Build).

Working on the package:

- Never create backup files. Build output and scratch files live in `/tmp` or in the
  git-ignored `notation/target`.
- Do not run git unless asked. Commit only with explicit relative paths, never `git add -A`.
- Quote paths, set `LC_ALL=C.UTF-8`, and wrap shell commands in `bash -c` when the user
  shell is Nushell.
- Do not create or edit `.org` files; this README is the documentation.

## Repo map

~~~
README.md          this file: the only documentation
AI-GUIDE.md        short guide for an AI writing .aiu files
AGENT.md           rules for an AI working on the package
types/             one starter .aiu page per file type, generated, never edited
notation system/   all the code; every command in this README runs from here
  notation/        Rust crate (parse, render, roundtrip) and Racket package (check, model)
    src/filetypes/        type loader, make-live.rkt, and types/ (one module per file type)
  tools/           see (viewer, aiu command, tv picker channel), aiu.nu (older script)
  gate/            the light gate: checks of the code itself
~~~

## Development

- Gate: `gate/check.nu`, run with Nushell. It checks parentheses, names, dependency
  direction, the Rust/Racket split, module loading and comments.
- One file, one job, a header comment, and a comment above every definition.

### Adding a feature

Keep this README short: change rows, never paste details here.

1. New block name: add it to `BLOCK_NAMES` in `notation/src/parser/parser.rs` and to the
   table in `notation/src/elements/register.rkt`. The two lists must agree.
2. New error: add it to `ErrorKind` in `parser.rs`, and one row to the errors table.
3. Change one row in the status table here.
4. Prove it with one real run of `check` on a page that uses the feature.
