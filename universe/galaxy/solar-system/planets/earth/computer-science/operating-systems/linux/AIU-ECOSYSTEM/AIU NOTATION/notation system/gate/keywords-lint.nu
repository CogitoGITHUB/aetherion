#!/usr/bin/env nu
# One job: every copy of the declaration keyword list matches the list in parser.rs.
#
# parser.rs holds the registered declaration keywords. The checker and the viewer keep
# copies. This stage reads the list in parser.rs, finds every list in the Racket files
# that holds at least MIN_HITS of those words, and fails when a copy has a word the
# parser does not know or lacks one it knows. When it finds no copy it prints
# NOTHING-TO-CHECK instead of OK.
#
# Style note: no mut, no bare parenthesis inside a string, no "not".

# The path of this script; the code lives one folder above gate/.
const gate_file = (path self)

# The fewest known keywords a list must hold to count as a copy of the keyword list.
const MIN_HITS = 4

# keyword_body reads the quoted words of the list that follows one mention of the keywords.
def keyword_body [lines: list<string>, start: int] {
  let rest = ($lines | skip ($start + 1))
  let body = ($rest | skip until {|l| $l | str contains "= ["} | skip 1 | take until {|l| ($l | str trim) == "];"})
  $body | str join " " | split row "\"" | enumerate | where {|x| ($x.index mod 2) == 1} | get item
}

# rust_keywords reads the quoted words of the keyword list in parser.rs.
def rust_keywords [parser: string] {
  let lines = (open --raw $parser | lines)
  let marks = ($lines | enumerate | where {|x| $x.item | str contains "registered declaration keywords"} | get index)
  let lists = ($marks | each {|m| keyword_body $lines $m} | where {|b| (($b | length) >= 8) and (($b | length) <= 30)})
  if ($lists | is-empty) { [] } else { $lists | first }
}

# words_of lists the keyword-shaped words of a text, the quoted ones or the bare symbols.
def words_of [text: string, quoted: bool] {
  let pattern = (if $quoted { "\"([a-z][a-z-]*)\"" } else { "([a-z][a-z-]*)" })
  try { $text | parse --regex $pattern | get capture0 } catch { [] }
}

# racket_lists returns every list of a Racket file that holds enough of the known keywords.
def racket_lists [file: string, keys: list<string>] {
  let text = (open --raw $file | lines | where {|l| ($l | str trim | str starts-with ";") == false} | str join "\n")
  let groups = (try { $text | parse --regex "(\\x27?)[\\(\\[]([^()\\[\\]]*)[\\)\\]]" } catch { [] })
  $groups | each {|g|
    let words = (words_of $g.capture1 ($g.capture0 == ""))
    let hits = ($words | where {|w| $keys | any {|k| $k == $w}} | uniq)
    if ($hits | length) >= $MIN_HITS {
      {extra: ($words | where {|w| ($keys | any {|k| $k == $w}) == false} | uniq), missing: ($keys | where {|k| ($words | any {|w| $w == $k}) == false})}
    } else { null }
  } | where {|e| $e != null}
}

# main compares every copy with the parser list, prints each difference and exits non-zero on any.
def main [] {
  let root = ($gate_file | path dirname | path dirname)
  let parser = ($root | path join notation src parser parser.rs)
  let keys = (rust_keywords $parser)
  if ($keys | length) < 8 {
    print "KEYWORDS - could not read the keyword list from parser.rs"
    exit 1
  }
  let files = (glob $"($root)/**/*.rkt" | where {|p| (($p | str contains "/tests/") == false) and (($p | str contains "/target/") == false)})
  let found = ($files | each {|f|
    let rel = ($f | path relative-to $root)
    racket_lists $f $keys | each {|l| {file: $rel, extra: $l.extra, missing: $l.missing}}
  } | flatten)

  if ($found | is-empty) {
    print "NOTHING-TO-CHECK keywords - found no second keyword list in the Racket files"
    exit 0
  }
  let bad = ($found | where {|l| (($l.extra | length) + ($l.missing | length)) > 0})
  for b in $bad {
    let extra = ($b.extra | str join ",")
    let missing = ($b.missing | str join ",")
    print $"KEYWORDS - ($b.file): unknown to parser.rs [($extra)], missing [($missing)]"
  }
  if ($bad | is-empty) {
    print $"OK keywords - ($keys | length) keywords in parser.rs, ($found | length) copies in Racket files agree"
    exit 0
  }
  exit 1
}
