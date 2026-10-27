# AIU NOTATION

A plain-text format for notes, documents and literate code. Files end in `.aiu`.

Everything sits inside a named block, so a person, a script and an AI read a file the same way, and a checker says what is wrong and on which line. Plain text stays the source of truth: any editor, `grep` and `git diff` work on it.

It is meant to replace Org, Markdown and LaTeX for the author's own writing.

AI agents: read README-AI.md first, not this file.

## 1. What you get

| Part | What it does |
|---|---|
| Format | `.aiu` files made of named blocks |
| Checker | `check` names every error with its line |
| Viewer | `see` shows a page as boxes in the terminal; `--contracts` puts each contract on the block it judges |
| Command | `aiu` wraps all of it, with tv menus |
| File types | a `kind:` limits blocks, demands sections, adds contracts |

## 2. Requirements

| Tool | Needed | Note |
|---|---|---|
| Rust (cargo) | yes | builds the parser |
| Racket 9 (CS) | yes | checker and viewer |
| Nushell | yes | the `aiu` script and the gate |
| tv (television) | no | command menu and page picker |

## 3. Quick start

~~~
cd "notation system"
cargo build --manifest-path notation/Cargo.toml
export AIU_NOTATION_BIN="$PWD/notation/target/debug/notation"
ln -s "$PWD/tools/see/aiu" ~/.local/bin/aiu
aiu check ../types/default.aiu
aiu see ../types/default.aiu
~~~

Set `AIU_NOTATION_BIN` in every new shell. Without it `check` exits with code 2.

## 4. A page in 20 seconds

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
Comments are blocks too. The viewer shows them as plain text.
comment end
section end
~~~

In the viewer: every block is a box named after its kind, the title box shows its tags, the section box is numbered `section 1 · A section` and holds its blocks, and no start or end lines show.

## 5. The rules

| # | Rule |
|---|---|
| 1 | Everything is inside a block. Text outside is `stray-text`. Only blank lines may sit between blocks. |
| 2 | A block is `name start`, content, `name end`. Markers are alone on their line, at column 0, lowercase, same name both times. |
| 3 | The first block of a file is a `title`. The first block of a `section` is its `title`. |
| 4 | Declarations are `keyword: value` lines straight under the start line. Only registered keywords count. |
| 5 | A `code` body is opaque. It may hold anything except the exact line `code end`. |
| 6 | Numbers are computed (1, 1.1, 1.2, 2). Never type them. |
| 7 | Nothing is repaired silently. A good file prints back byte for byte. |

## 6. Blocks

| Block | Purpose |
|---|---|
| `title` | one line; file title and section titles; `tags:` goes under its start line |
| `paragraph` | prose; the viewer joins and wraps lines; a blank line starts a new paragraph |
| `section` | a title first, then paragraph, code, comment or section blocks |
| `code` | text kept exactly; `language:` under its start line |
| `comment` | a note for readers; shown as plain text; never put a line `x start` or `x end` inside |
| `heading` | older flat heading with `level:`; being replaced by `section`; do not write new ones |
| `table`, `header`, `row` | parsed, but `check` rejects them; do not use yet |

Run `aiu list` for the live list.

## 7. Declarations

| Keyword | On | Values |
|---|---|---|
| `tags` | `title` | `a b c` |
| `kind` | file `title` | a file type name |
| `language` | `code` | any language name |
| `style` | `paragraph`, `title` | `bold`, `dim`, `italic`, `underline` (several, space separated) |
| `color` | `paragraph`, `title` | `red green yellow blue magenta cyan white gray` |
| `theme`, `format`, `font` | any | accepted, ignored by terminals |

Registered but not verified, do not use: `level`, `caption`, `column`, `cell`, `row-id`, `meta`, `todo`.

## 8. File types

A page picks a type with `kind: NAME` under its title start line. `check` then rejects any block the type does not allow. No `kind:` means no type check.

| Type | Required top-level sections, in order |
|---|---|
| `decision` | Context, Options, Decision, Consequences |
| `plan` | Goal, Steps, Done when, Open questions |
| `research` | Abstract, Introduction, Methods, Results, Discussion, References |
| `module` | Purpose, Code |
| `note` | none allowed |
| `book`, `journal`, `todo`, `default` | no required sections |

Other sections may follow the required ones. Starter pages live in `types/` (generated, never edited by hand).

### Contracts

Every type carries contracts: checked rules and unchecked questions.

| Kind | Entry | Result |
|---|---|---|
| rule | `(rule SECTION BLOCK NAME ARG)` | `rule-violated` when broken |
| question | `(question SECTION BLOCK TEXT)` | `question-unverified`, only with `AIU_QUESTIONS=1` |

Rule names: `max-words`, `min-words`, `max-lines`, `must-match`, `must-not-match`, `needs-declaration`. SECTION is a section title or `"*"` for any. Nothing is ever edited to satisfy a contract.

`aiu see FILE --contracts` adds a panel: each contract with its state (`holds in N blocks`, `BROKEN, line L`, `no matching block`, `not verified`), then the findings.

### Make a type

~~~
aiu newtype NAME
~~~

Then set the description, allowed blocks and contracts in `notation/src/filetypes/types/NAME.rkt` and run `aiu update`.

## 9. The aiu command

| Command | Does |
|---|---|
| `aiu` | tv menu of all commands, with a preview of each |
| `aiu see FILE` | boxed view (`--plain`, `--width N`, `--contracts`) |
| `aiu check FILE` | check a page |
| `aiu open FILE` | open in the editor |
| `aiu render FILE` | plain text render |
| `aiu parse FILE` | parse tree |
| `aiu roundtrip FILE` | byte-exact round trip test |
| `aiu pick [FOLDER]` | tv page picker; the preview shows the contracts panel |
| `aiu list` | blocks and file types that exist now |
| `aiu new TYPE FILE` | new page from a type starter, checked |
| `aiu newtype NAME` | new file type from the template |
| `aiu update` | rebuild the binary and regenerate `types/` if stale |
| `aiu gate` | run the light gate |

Exit codes of `check`: 0 clean, 1 errors found, 2 could not run.

### Environment

| Variable | Effect |
|---|---|
| `AIU_NOTATION_BIN` | path of the Rust binary (required) |
| `AIU_RACKET` | Racket binary; when unset, `aiu` uses `~/opt/racket-full/bin/racket` if it exists, else `racket` from PATH |
| `aiutd`, else `AIU_EDITOR`, else `EDITOR` | editor used by `aiu open` |
| `AIU_QUESTIONS=1` | report contract questions |
| `AIU_PICK_FIRST=1` | skip the picker, take the first page |
| `LC_ALL=C.UTF-8` | set it, or Racket garbles non-ASCII paths |

## 10. Errors

Fix one error at a time from the top. Later ones may disappear.

| Error | Meaning | Fix |
|---|---|---|
| `stray-text` | text outside a block, or loose in a section | put it in a block |
| `mismatched-end` | end name differs from the open block | fix the name |
| `unclosed-block` | block never closed | add its end line |
| `unknown-block-name` | parser does not know the name | use a listed block |
| `unknown-element-name` | checker table does not know the name | same |
| `missing-title` | file or section lacks a first `title` | start with `title start` |
| `bad-heading-level` | old `heading` level is not a whole number | write 1, 2, 3 |
| `unknown-file-type` | `kind:` names no module | use an existing type |
| `block-not-in-type` | block not allowed by the type | change block or kind |
| `section-missing` | required section absent | add it |
| `section-out-of-order` | required sections in wrong order | reorder |
| `rule-violated` | a contract rule is broken | change the block |
| `question-unverified` | a contract question needs a judge | a person or AI decides |

`parser-recovery ... column unknown` is normal; the line number is right.

## 11. Coming from Org, Markdown or LaTeX

| You want | Org | Markdown | LaTeX | `.aiu` |
|---|---|---|---|---|
| file title | `#+TITLE:` | `# Title` | `\title{}` | first `title` block |
| tags | `:tag:` | front matter | none | `tags:` under the title |
| sections | `*` `**` | `#` `##` | `\section` | nested `section` blocks |
| section numbers | exporter | none | automatic | computed |
| code | `#+BEGIN_SRC` | backticks | `lstlisting` | `code` with `language:` |
| comment | `# line` | `<!-- -->` | `%` | `comment` block |
| bold, italic, links | `*b*` | `**b**` | `\textbf{}` | not built |
| lists | `- item` | `- item` | `itemize` | not built |
| tables | pipes | pipes | `tabular` | `table`, unverified |
| math | fragments | `$..$` | native | far future |
| include a file | `#+INCLUDE:` | none | `\input` | planned |

## 12. Status

| Feature | State |
|---|---|
| title, paragraph, section, code, comment | works |
| declarations (tags, language, style) | works |
| stray text and section title errors | works |
| exact round trip | works |
| viewer `see`, shows comments | works |
| boxed viewer, contracts shown on the blocks they judge | works |
| `aiu` command, tv picker and menus | works |
| `aiu update`, `list`, `gate`, `new`, `newtype` | works |
| `render` keeps every line of a code body, marker-looking lines included | works |
| `check` errors name the right line and column, and the end-line wording is `NAME end` | works |
| file types, required sections, contracts | works |
| section numbers | viewer only; the checker still counts `heading` |
| tables | parser only |
| literate code, JSON, todos, rich render, editor surface, security rules | written by earlier AI sessions, not verified |
| inline bold, italic, links | not built |
| math and graphs | far future |
| include another file | planned |
| editor hosting | planned, separate project |
| `aiu update` from upstream | planned |
| kit: MCP server, skill, plugin | planned |

Known gaps:

- The viewer and the checker keep separate keyword lists; the gate stage `keywords` fails when they differ.
- Underline under a numbered heading is one character too long (`--flat` only; the boxes have none).

## 13. Repo map

| Path | Holds |
|---|---|
| `README.md` | this guide |
| `README-AI.md` | guide for AI agents |
| `types/` | one generated starter page per file type |
| `notation system/notation/` | Rust crate (parse, render, roundtrip) and Racket package (check, model) |
| `notation system/notation/src/filetypes/` | type loader, `make-live.rkt`, `types/` |
| `notation system/tools/see/` | viewer, `aiu`, tv channels in `cable/` |
| `notation system/gate/` | light gate, checks of the code itself |
