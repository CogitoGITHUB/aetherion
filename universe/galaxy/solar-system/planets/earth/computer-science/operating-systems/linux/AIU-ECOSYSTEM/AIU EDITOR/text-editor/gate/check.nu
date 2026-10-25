#!/usr/bin/env nu
# One job: the dispatcher — named stages, one table, --list.
# Registered in plan/package-tree.org. check.nu is the only gate entry point;
# no other script may be the thing someone runs "by hand" instead.
#
# Two rules this file keeps:
#   1. A stage with nothing to check prints NOTHING-TO-CHECK and never PASS.
#   2. The dispatcher prints how many stages checked nothing, so a green run
#      never hides a stage that did not look at anything.
# Stages need no edit here to start checking for real: each lint decides for
# itself whether it has something to check.
#
# No mutable variables: this phone's Nu has none, so results are collected as a
# list and counted from it. Every gate script follows that rule.

use ./env.nu *

# The stages the light gate runs, in order, with the script that runs each
# one and the kind of script it is.
const STAGES = [
    {name: "paren-check", script: "read-check.rkt", kind: "racket"}
    {name: "load-check", script: "load-check.rkt", kind: "racket-plain"}
    {name: "naming", script: "banned-words-lint.nu", kind: "nu"}
    {name: "one-way", script: "one-way-dependency-lint.nu", kind: "nu"}
    {name: "security-gate", script: "security-gate-lint.nu", kind: "nu"}
    {name: "language-split", script: "language-split-lint.nu", kind: "nu"}
    {name: "comment-lint", script: "comment-lint.nu", kind: "nu"}
    {name: "route-check", script: "route-check.rkt", kind: "racket-plain"}
    {name: "explorer-check", script: "explorer-check.rkt", kind: "racket-plain"}
    {name: "key-check", script: "key-check.rkt", kind: "racket-plain"}
    {name: "dashboard-check", script: "dashboard-check.rkt", kind: "racket-plain"}
    {name: "secret-check", script: "secret-check.rkt", kind: "racket-plain"}
    {name: "kit-check", script: "kit-check.rkt", kind: "racket-plain"}
    {name: "plugin-check", script: "plugin-check.rkt", kind: "racket-plain"}
    {name: "send-check", script: "send-check.rkt", kind: "racket-plain"}
    {name: "git-check", script: "git-check.rkt", kind: "racket-plain"}
]

# run-one stage returns what happened, and never raises: a stage that fails is
# a result to print, not an error that stops the dispatcher. The stderr is
# kept, because a stage that fails silently is a lie about what failed.
def run-one [stage] {
    if $stage.kind == "racket" {
        let files = (rkt_files)
        if ($files | is-empty) {
            {name: $stage.name, code: 0, out: "NOTHING-TO-CHECK paren-check: no Racket files exist yet", err: ""}
        } else {
            let r = (try { run-external (racket_bin) $"($gate_dir)/($stage.script)" ...$files | complete }
                     catch {|e| {stdout: $"(racket_bin) could not run: ($e)", stderr: "", exit_code: 3} })
            {name: $stage.name, code: $r.exit_code, out: ($r.stdout | str trim), err: ($r.stderr | str trim)}
        }
    } else if $stage.kind == "racket-plain" {
        let r = (try { run-external (racket_bin) $"($gate_dir)/($stage.script)" | complete }
                 catch {|e| {stdout: $"(racket_bin) could not run: ($e)", stderr: "", exit_code: 3} })
        {name: $stage.name, code: $r.exit_code, out: ($r.stdout | str trim), err: ($r.stderr | str trim)}
    } else {
        let r = (try { run-external nu $"($gate_dir)/($stage.script)" | complete }
                 catch {|e| {stdout: $"(nu) could not run ($stage.script): ($e)", stderr: "", exit_code: 3} })
        {name: $stage.name, code: $r.exit_code, out: ($r.stdout | str trim), err: ($r.stderr | str trim)}
    }
}

# locale-is-utf8 answers whether a locale name says UTF-8.
def locale-is-utf8 [name] {
    ($name | str lowercase | str contains "utf")
}

# ensure-utf8-locale answers a locale this machine has that speaks UTF-8, or
# an empty text when there is none. It exists because the project path holds
# "Æ": a child spawned under the C locale receives the path with that
# character replaced by "??", so the check opens a file that is not there and
# the gate reports a failure that belongs to the environment, not the code.
def ensure-utf8-locale [] {
    let named = ([($env.LANG? | default "") ($env.LC_ALL? | default "")] | where {|l| locale-is-utf8 $l })
    if (not ($named | is-empty)) {
        $named | first
    } else {
        let available = (^locale -a | lines | where {|l| locale-is-utf8 $l })
        if ($available | is-empty) { "" } else { $available | first }
    }
}

# main runs every stage and prints each one's output plus the verdict; with
# --list it only names the stages and the scripts they run.
def main [ --list ] {
    if $list {
        print $"the light gate has ($STAGES | length) stages:"
        for s in $STAGES {
            print $"  ($s.name)  ->  ($s.script)  [($s.kind)]"
        }
        exit 0
    }

    # The gate's locale is set once here, before any stage spawns a child,
    # and it is named: a stage that cannot be given one must say so, never go
    # red with an empty answer. See ensure-utf8-locale for the reason.
    let utf8 = (ensure-utf8-locale)
    if ($utf8 | is-empty) {
        print "the gate cannot run: this machine has no UTF-8 locale, and the project path holds Æ — a child under the C locale receives that path as ??therion and every stage that spawns a child would report a false failure"
        exit 3
    }
    $env.LANG = $utf8
    $env.LC_ALL = $utf8
    print $"the gate's locale: ($utf8) — the project path holds Æ, and a child under the C locale receives it as ??therion"

    let results = ($STAGES | each {|s| run-one $s })

    for r in $results {
        print $"--- ($r.name)"
        print $r.out
        # A stage that exits nonzero with nothing to say must not vanish: the
        # dispatcher prints the reason the child gave, or says the child gave
        # none, so a red run is never a blank line.
        if ($r.code != 0) and ($r.out | is-empty) {
            print (if ($r.err | is-empty) {
                "the stage exited nonzero and said nothing"
            } else {
                $r.err
            })
        }
    }

    let red = ($results | where {|r| $r.code != 0 } | length)
    let nothing = ($results | where {|r| $r.out =~ "NOTHING-TO-CHECK" } | length)

    print $"stages that checked nothing: ($nothing) of ($STAGES | length)"
    if $nothing > 0 {
        print "NOTHING-TO-CHECK above means the stage had nothing to check, not that the rule held"
    }
    let verdict = if $red == 0 { $"light gate: green, ($STAGES | length) stages ran" } else { $"light gate: red, ($red) of ($STAGES | length) stages" }
    print $verdict
    exit (if $red == 0 { 0 } else { 1 })
}
