# Writing .aiu files: guide for AI agents

Read this whole file before you create or edit a `.aiu` file. About the package itself,
read `README.md`. This guide lists only what is verified to work today. If a feature is
not listed here, do not use it.

## The loop

1. Write the file using only the blocks below.
2. Run the check. Fix every error it prints. Run it again until it says no errors.
3. Report the real output of the last check. Never say a file is valid without it.

Check, from the project folder (quote paths; the folder name contains a space):

~~~
export AIU_NOTATION_BIN="$PWD/notation/target/debug/notation"
LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check "FILE"
~~~

- If `racket` is not found, use `/root/home/shape/opt/racket-full/bin/racket`.
- If the binary is missing, build it: `cargo build --manifest-path notation/Cargo.toml`.
- Exit codes of `check`: 0 clean, 1 errors found, 2 could not run (missing file or binary).
- View the finished page: `LC_ALL=C.UTF-8 racket tools/see/see.rkt "FILE"`.
- The shortcuts `aiu check FILE`, `see FILE` and `newaiu FILE` exist only in the author's
  Nushell. Do not rely on them.

## Template

~~~
title start
tags: topic
Title of the file
title end

paragraph start
Prose goes here, in a few lines.
paragraph end

section start
title start
Title of the section
title end
paragraph start
Text of the section.
paragraph end
code start
language: text
anything, kept exactly as written
code end
section end
~~~

## Hard rules

1. Every line of text sits inside a block. Text outside any block is an error. Only blank
   lines may sit between blocks.
2. A block is `name start`, content, `name end`. Each marker is alone on its line, at
   column 0, lowercase, exactly two words, and the same name on both lines.
3. The first block of the file is a `title`.
4. A `section` holds blocks. The first block inside a section is its `title`. Loose text
   directly inside a section is an error.
5. Declarations are `keyword: value` lines directly under a start line, with nothing
   between. One per line.
6. A code body is opaque: it may contain anything except the exact line `code end`.
7. Never type section numbers or put numbers in titles. They are computed.
8. Use only the block names below. An unknown name is an error.

## Blocks you may use

| Block | Use |
|---|---|
| `title` | one line of text; `tags: a b` may sit under its start line |
| `paragraph` | prose; a few lines is fine, the viewer joins and wraps them; a blank line inside starts a new paragraph |
| `section` | holds a title first, then paragraph, code, comment or section blocks |
| `code` | text kept exactly; put `language: name` under its start line |
| `comment` | a note for readers; hidden by the viewer; never put a line `x start` or `x end` inside one |

## Declarations you may use

- `tags: a b c` on a `title` block
- `language: name` on a `code` block
- `style: bold` (or dim, italic, underline; several separated by spaces) on a `paragraph`
  or `title`
- `color: green` (red, green, yellow, blue, magenta, cyan, white, gray) on a `paragraph`
  or `title`
- `theme`, `format` and `font` are accepted hints that terminals ignore

Any other line like `word: text` is plain content, which is fine. Do not use the
declaration keywords made for tables and todos.

## File types

- `kind: book` or `kind: notes` under the title's start line holds the page to that type
- a `book` page may only use title, section, paragraph, code and comment blocks
- no `kind:` line means no type check

## Not built: do not write

- bold, italic or link markup inside a paragraph: write plain text
- lists, tables, math, includes of other files
- `status:` lines
- `heading`, `table`, `header` and `row` blocks
- any block name that is not in the table above

## Common mistakes

- text between blocks: put it in a `paragraph` block
- the file or a section not starting with a `title` block
- an end line whose name differs from its start line
- a prose line that is exactly `something start` or `something end`: it is read as a
  block marker. Put such lines inside a `code` block
- numbers typed into section titles
- a `keyword: value` line that is not directly under a start line
- inventing block names

## Reading the check output

- `parser-recovery: the parser recovered from X` means error X. `column unknown` is
  normal. The line number is right.
- `$AIU_NOTATION_BIN parse FILE` prints the parse tree; its `error` lines give the kind,
  the line and what to do.
- Fix one error at a time from the top; later errors may disappear.

## Do not

- Edit anything under `notation/`, `gate/`, `plan/` or `tools/` unless the user asked for
  it.
- Create files outside what the user asked for.
- Claim a file is valid without the real output of the check.
