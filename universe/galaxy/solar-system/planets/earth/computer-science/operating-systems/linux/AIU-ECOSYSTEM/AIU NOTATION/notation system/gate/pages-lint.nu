#!/usr/bin/env nu
# One job: every .aiu page in the repo checks clean and prints back byte for byte.
#
# The starter pages in types/ are generated from the file types, so a parser change
# that breaks one is a real regression. This stage runs check on every page and, when
# ROUNDTRIP is on, compares the round trip output with the file itself.
#
# Style note: no mut, no bare parenthesis inside a string, no "not".

use ./env.nu *

# The path of this script; the repo root is two folders above gate/.
const gate_file = (path self)

# Whether the round trip output is compared with the file; set when the stage was written.
const ROUNDTRIP = false

# page_files lists every .aiu page of the repo outside build and git folders.
def page_files [repo: string] {
  glob $"($repo)/**/*.aiu" | where {|p| (($p | str contains "/target/") == false) and (($p | str contains "/.git/") == false)}
}

# run_check runs the real check on one page and returns its exit code and text.
def run_check [racket: string, cli: string, bin: string, page: string] {
  with-env {LC_ALL: "C.UTF-8", AIU_NOTATION_BIN: $bin} { run-external $racket $cli "check" $page | complete }
}

# round_trip_ok answers whether the round trip prints the page back unchanged.
def round_trip_ok [bin: string, page: string] {
  let r = (with-env {LC_ALL: "C.UTF-8"} { run-external $bin "roundtrip" $page | complete })
  ($r.exit_code == 0) and ($r.stdout == (open --raw $page))
}

# main checks every page and exits non-zero when any page fails.
def main [] {
  let root = ($gate_file | path dirname | path dirname)
  let repo = ($root | path dirname)
  let bin = ($root | path join notation target debug notation)
  let cli = ($root | path join notation src entry cli.rkt)
  let pages = (page_files $repo)

  if ($pages | is-empty) {
    print "NOTHING-TO-CHECK pages - no .aiu pages exist"
    exit 0
  }
  if (($bin | path exists) == false) {
    print "PAGES - the Rust binary is not built: run aiu update"
    exit 1
  }
  let racket = (racket_bin)
  let bad = ($pages | each {|p|
    let c = (run_check $racket $cli $bin $p)
    let rel = ($p | path relative-to $repo)
    if $c.exit_code != 0 {
      let first = (($c.stdout + $c.stderr) | lines | append "no output" | first)
      {page: $rel, why: $"check failed: ($first)"}
    } else if $ROUNDTRIP and ((round_trip_ok $bin $p) == false) {
      {page: $rel, why: "the round trip is not byte for byte"}
    } else { null }
  } | where {|e| $e != null})

  if ($bad | is-empty) {
    let how = (if $ROUNDTRIP { "check clean and round trip exact" } else { "check clean" })
    print $"OK pages - ($pages | length) pages, ($how)"
    exit 0
  }
  for b in $bad { print $"PAGES - ($b.page): ($b.why)" }
  exit 1
}
