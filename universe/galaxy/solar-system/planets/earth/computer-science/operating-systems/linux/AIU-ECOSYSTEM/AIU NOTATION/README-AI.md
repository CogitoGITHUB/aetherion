# AIU NOTATION: guide for AI agents

Read this whole file before doing anything. It is the working contract for any AI that writes `.aiu` pages or changes this package.

## 1. Hard rules

| Rule |
|---|
| Use only what this guide lists as working. If a feature is not listed, do not use it. |
| Work only inside this project folder. Other projects are read-only. A parent rules file wins over this guide. |
| Do not create files outside what the user asked for. |
| Do not edit anything under `notation/`, `gate/` or `tools/` unless the user asked. |
| Never create backup files. Scratch and build output go in `/tmp` or in `notation/target`. |
| Do not run git unless asked. When asked: commit explicit relative paths of your own files, never `git add -A`, push only if asked, never force past a lock. |
| Do not create or edit `.org` files. |
| Never edit `types/*.aiu` by hand. They are generated. |
| Read in small pieces, never whole large files. Reports are short and show real output. |
| Never say a file is valid without the real output of the last `check`. |
| Quote paths (the folder name has a space). Set `LC_ALL=C.UTF-8`. If the user shell is Nushell, wrap commands in `bash -c`. |
| Anything printed in a terminal or tv preview must wrap to the screen width. |

## 2. Environment

~~~
cd "notation system"
cargo build --manifest-path notation/Cargo.toml
export AIU_NOTATION_BIN="$PWD/notation/target/debug/notation"
~~~

| Variable | Effect |
|---|---|
| `AIU_NOTATION_BIN` | Rust binary; without it `check` exits 2 |
| `AIU_RACKET` | Racket binary if `racket` is not on PATH |
| `AIU_QUESTIONS=1` | report contract questions |
| `AIU_PICK_FIRST=1` | skip the picker (scripts) |
| `LC_ALL=C.UTF-8` | needed for non-ASCII paths |

The shortcut `aiu` exists only where the owner installed it. Without it use the raw commands in section 6.

## 3. Writing .aiu pages

Run `aiu list` first to see the blocks and file types that exist now.

The loop:

1. Write the file using only the blocks below.
2. Run `check`. Fix every error. Run it again until clean.
3. Report the real output of the last check.

### Format

| Rule |
|---|
| Everything is inside a block `name start` ... `name end`. Markers alone on a line, column 0, lowercase, same name. |
| Only blank lines between blocks. Other text is `stray-text`. |
| A file starts with a `title` block. A `section` starts with a `title` block. No loose text in a section. |
| `keyword: value` declarations go directly under the start line, one per line, nothing between. |
| `code` bodies are opaque, except the exact line `code end`. |
| Never type numbers, not even in titles. They are computed. |

### Allowed blocks

| Block | Use |
|---|---|
| `title` | one line; `tags:` under its start line |
| `paragraph` | prose |
| `section` | title first; then paragraph, code, comment, section |
| `code` | `language:` under its start line |
| `comment` | note for readers; never put a line `x start` or `x end` inside |

### Allowed declarations

| Keyword | On | Values |
|---|---|---|
| `tags` | `title` | `a b c` |
| `kind` | file `title` | an existing type |
| `language` | `code` | language name |
| `style` | `paragraph`, `title` | bold, dim, italic, underline |
| `color` | `paragraph`, `title` | red green yellow blue magenta cyan white gray |

### Do not write

- bold, italic or link markup inside a paragraph (plain text only)
- lists, tables, math, includes of other files
- `status:` lines
- `heading`, `table`, `header`, `row` blocks
- the keywords `level`, `caption`, `column`, `cell`, `row-id`, `meta`, `todo`
- invented block names

### Common mistakes

| Mistake | Fix |
|---|---|
| text between blocks | put it in a `paragraph` |
| file or section without a first `title` | add it |
| end name differs from start name | match them |
| a prose line that is exactly `something start` or `something end` | put it inside a `code` block |
| numbers in section titles | remove them |
| `keyword: value` not under a start line | move it or make it a plain line |

### File types

| Type | Required top-level sections, in order |
|---|---|
| `decision` | Context, Options, Decision, Consequences |
| `plan` | Goal, Steps, Done when, Open questions |
| `research` | Abstract, Introduction, Methods, Results, Discussion, References |
| `module` | Purpose, Code |
| `note` | no sections allowed |
| `book`, `journal`, `todo`, `default` | none required |

With `kind: NAME` under the title start line, `check` rejects blocks the type forbids. Start from `aiu new TYPE FILE`; it copies the starter and checks it. Contracts: rules (`max-words`, `min-words`, `max-lines`, `must-match`, `must-not-match`, `needs-declaration`) are checked and give `rule-violated`; questions are only reported with `AIU_QUESTIONS=1` and need a human or AI judgment. Never edit a page just to silence a contract without being asked.

## 4. Errors

Fix one at a time from the top. `$AIU_NOTATION_BIN parse FILE` prints the tree with `error` lines (kind, line, what to do).

| Error | Fix |
|---|---|
| `stray-text` | put the text in a block |
| `mismatched-end` | fix the end name, or close the inner block first |
| `unclosed-block` | add the end line |
| `unknown-block-name` / `unknown-element-name` | use a name from the blocks table |
| `missing-title` | start the file or section with `title start` |
| `bad-heading-level` | write 1, 2, 3 |
| `unknown-file-type` | use an existing type, or make it |
| `block-not-in-type` | use an allowed block, or change the kind |
| `section-missing` | add a section with that title |
| `section-out-of-order` | reorder the sections |
| `rule-violated` | change the block; the checker never edits |
| `question-unverified` | a person or an AI judges it |

`parser-recovery: the parser recovered from X` just means error X. `column unknown` is normal; the line is right. Other findings (`tag-names-nothing`, `property-no-value`, `link-no-target`) are unverified.

## 5. Working on the package

### Code rules

- One file, one job, a header comment, and a comment above every definition. The gate enforces this.
- Keep this guide and the human README short: change rows, never paste details.

### Adding things

| Change | Steps |
|---|---|
| New block | add to `BLOCK_NAMES` in `notation/src/parser/parser.rs` and the table in `notation/src/elements/register.rkt` (gate stage `register` fails if they differ; `table`, `header`, `row` are the only exceptions, listed in `gate/register-lint.nu`) |
| New error | add to `ErrorKind` in `parser.rs`, add one row to the errors table |
| New keyword | add to the lists in `parser.rs`, `model/properties.rkt`, `data/json.rkt` (gate stage `keywords` fails if they differ) |
| New file type | `aiu newtype NAME`, then set description, allowed blocks, contracts in `notation/src/filetypes/types/NAME.rkt`, then `aiu update` |
| New aiu command | a line in `tools/see/cable/aiu-commands.txt` (name;usage;description) and a row in the `aiu-help` table of the script |

Every change ends with: one status row updated, and one real `check` run on a page that uses the feature.

### New file type details

- The type module requires `"_base.rkt"` and provides `the-type` and `the-contracts`. Fields of `file-type`: name, one-line description, allowed block names (`#f` allows any).
- Only list blocks the parser knows.
- `the-contracts` needs at least one entry, or the gate fails.
- Required sections: also export `the-sections`, a list of titles.
- A type needing more modules becomes a folder `types/NAME/type.rkt` (see `types/book/`). Names starting with `_` are ignored (safe scratch).
- `aiu update` never deletes pages. When removing a type, delete its page in `types/` by hand.

### Viewer and cache

- After any `.rkt` change run `raco make tools/see/see.rkt notation/src/entry/cli.rkt` (raco sits beside racket). A render then takes about 3 to 5 s on the phone instead of 11 s.
- The preview cache `/tmp/aiu-preview` is keyed on page, time, width and flags, not on `see.rkt`. After changing the viewer run `rm -rf /tmp/aiu-preview`.
- Racket on the author phone: `/root/home/shape/opt/racket-full/bin/racket`.
- tv crashes when the shell captures its output. Choices go through files in `/tmp` (`aiu-cmd`, `aiu-type`, `aiu-pick`). Never use `$(tv ...)` or `| str trim` on tv.
- Previews wrap through `tools/see/fitwidth.sh`; page previews through `tools/see/preview-fit.sh`.

## 6. Commands

Run from the `notation system/` folder.

| Task | Command |
|---|---|
| Check a page | `LC_ALL=C.UTF-8 racket notation/src/entry/cli.rkt check FILE` |
| View a page | `LC_ALL=C.UTF-8 racket tools/see/see.rkt FILE` (`--plain`, `--width N`, `--contracts`) |
| Plain render | `$AIU_NOTATION_BIN render FILE` |
| Parse tree | `$AIU_NOTATION_BIN parse FILE` |
| Round trip | `$AIU_NOTATION_BIN roundtrip FILE` |
| Regenerate starters | `LC_ALL=C.UTF-8 racket notation/src/filetypes/make-live.rkt` |
| Gate | `nu gate/check.nu` |
| With `aiu` | `aiu check, see, render, parse, roundtrip, pick, list, new, newtype, update, gate` |

`check` exits 0 clean, 1 errors, 2 could not run. `tools/aiu.nu` is an older script; prefer the commands above. `render-rich`, `todos` and other `cli.rkt` commands were written by earlier sessions and are unverified.

## 7. The gate

`nu gate/check.nu` (or `aiu gate`) prints each stage as soon as it ends. It checks: parentheses, names, dependency direction, the Rust/Racket split, module loading, comments, file type tests, parser and register block names agree, every page checks clean and round trips exactly, keyword lists agree.

## 8. Status

| Feature | State |
|---|---|
| title, paragraph, section, code, comment | works |
| declarations, stray text, section title rule, round trip | works |
| viewer `see` (shows comments), `aiu`, tv picker and menus | works |
| `aiu update`, `list`, `gate`, `new`, `newtype` | works |
| file types, required sections, contracts | works |
| `heading` with `level:` | parsed; replaced by `section` |
| tables | parser accepts, checker rejects |
| section numbers | viewer only; checker still counts `heading` |
| literate code, JSON, todos, rich render, editor surface, security rules | unverified |
| inline markup, lists, math, includes | not built |
| editor hosting, upstream fetch, MCP server, skill, plugin | planned |

Known gaps:

- `render` drops a code line that looks like a block marker (fix is in `strip.rs`); file, `check` and round trip are correct.
- Viewer and checker keep separate keyword lists; the gate stage `keywords` catches drift.
- Viewer underline under a numbered heading is one character too long.
- The `parser-recovery ... column unknown` wording is clumsy.

## 9. Repo map

| Path | Holds |
|---|---|
| `README.md` | guide for people |
| `README-AI.md` | this file |
| `types/` | generated starter pages, never edited |
| `notation system/notation/` | Rust crate (parse, render, roundtrip), Racket package (check, model) |
| `notation system/notation/src/filetypes/` | loader, `make-live.rkt`, `types/` |
| `notation system/tools/see/` | viewer, `aiu`, tv channels in `cable/` |
| `notation system/gate/` | the light gate |

## 10. Report format

Short. State what changed, then the real output of the last `check` or gate run. No recap of steps.
