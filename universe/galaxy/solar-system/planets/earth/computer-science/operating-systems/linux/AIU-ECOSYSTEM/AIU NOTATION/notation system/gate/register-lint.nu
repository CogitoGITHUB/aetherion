#!/usr/bin/env nu
# One job: the block names of parser.rs and register.rkt must agree.
#
# parser.rs lists every block name the Rust parser accepts. register.rkt lists every
# name the checker knows. A name in one and not the other is a bug, except the names in
# PARSED_ONLY, which the parser accepts and the checker rejects on purpose. It also
# fails when a PARSED_ONLY name gets registered, so the exception list cannot go stale.
#
# Style note: no mut, no bare parenthesis inside a string, no "not".

# The path of this script; the code lives one folder above gate/.
const gate_file = (path self)

# The block names the parser accepts and the checker rejects on purpose.
const PARSED_ONLY = ["table" "header" "row"]

# rust_names reads the quoted names inside the BLOCK_NAMES list of parser.rs.
def rust_names [parser: string] {
  let body = (open --raw $parser | lines | skip until {|l| $l | str contains "BLOCK_NAMES: ["} | skip 1 | take until {|l| ($l | str trim) == "];"})
  $body | str join " " | split row "\"" | enumerate | where {|x| ($x.index mod 2) == 1} | get item
}

# racket_names reads the name of every element row in the table of register.rkt.
def racket_names [register: string] {
  open --raw $register | lines | parse --regex "\\(element .([a-z-]+) " | get capture0
}

# main compares the two lists, prints every difference and exits non-zero on any.
def main [] {
  let root = ($gate_file | path dirname | path dirname)
  let parser = ($root | path join notation src parser parser.rs)
  let register = ($root | path join notation src elements register.rkt)
  let rust = (rust_names $parser)
  let rkt = (racket_names $register)

  if ($rust | is-empty) or ($rkt | is-empty) {
    print "REGISTER - could not read the block names from parser.rs or register.rkt"
    exit 1
  }

  let only_rust = ($rust | where {|n| ($rkt | any {|r| $r == $n}) == false and (($PARSED_ONLY | any {|p| $p == $n}) == false)})
  let only_rkt = ($rkt | where {|n| ($rust | any {|r| $r == $n}) == false})
  let stale = ($PARSED_ONLY | where {|n| $rkt | any {|r| $r == $n}})
  let bad = ($only_rust | length) + ($only_rkt | length) + ($stale | length)

  if $bad == 0 {
    print $"OK register - ($rust | length) parser names, ($rkt | length) registered, ($PARSED_ONLY | length) parsed-only on purpose"
    exit 0
  }

  for n in $only_rust { print $"REGISTER - ($n) is in parser.rs but not registered in register.rkt" }
  for n in $only_rkt { print $"REGISTER - ($n) is registered in register.rkt but not in parser.rs" }
  for n in $stale { print $"REGISTER - ($n) is registered, so remove it from PARSED_ONLY in gate/register-lint.nu" }
  exit 1
}
