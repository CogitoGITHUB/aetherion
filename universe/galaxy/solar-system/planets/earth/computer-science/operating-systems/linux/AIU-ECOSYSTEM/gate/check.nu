#!/usr/bin/env nu

use ./env.nu *

const STAGES = [
    {name: "one-way", script: "one-way-dependency-lint.nu", kind: "nu"}
    {name: "security-gate", script: "security-gate-lint.nu", kind: "nu"}
    {name: "language-split", script: "language-split-lint.nu", kind: "nu"}
    {name: "route-check", script: "route-check.rkt", kind: "racket-plain"}
    {name: "explorer-check", script: "explorer-check.rkt", kind: "racket-plain"}
    {name: "key-check", script: "key-check.rkt", kind: "racket-plain"}
    {name: "notation-check", script: "notation-check.rkt", kind: "racket-plain"}
    {name: "secret-check", script: "secret-check.rkt", kind: "racket-plain"}
    {name: "kit-check", script: "kit-check.rkt", kind: "racket-plain"}
    {name: "send-check", script: "send-check.rkt", kind: "racket-plain"}
    {name: "git-check", script: "git-check.rkt", kind: "racket-plain"}
    {name: "pm-compile", script: "pm-compile-check.rkt", kind: "racket-plain"}
    {name: "test-check", script: "test-check.rkt", kind: "racket-plain"}
]

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

def locale-is-utf8 [name] {
    ($name | str lowercase | str contains "utf")
}

def ensure-utf8-locale [] {
    let named = ([($env.LANG? | default "") ($env.LC_ALL? | default "")] | where {|l| locale-is-utf8 $l })
    if (not ($named | is-empty)) {
        $named | first
    } else {
        let available = (^locale -a | lines | where {|l| locale-is-utf8 $l })
        if ($available | is-empty) { "" } else { $available | first }
    }
}

def main [ --list, --only: string = "", --level: int = 0 ] {
    if $list {
        print $"the light gate has ($STAGES | length) stages:"
        for s in $STAGES {
            print $"  ($s.name)  ->  ($s.script)  [($s.kind)]"
        }
        exit 0
    }

    let utf8 = (ensure-utf8-locale)
    if ($utf8 | is-empty) {
        print "the gate cannot run: this machine has no UTF-8 locale, and the project path holds Æ — a child under the C locale receives that path as ??therion and every stage that spawns a child would report a false failure"
        exit 3
    }
    $env.LANG = $utf8
    $env.LC_ALL = $utf8
    print $"the gate's locale: ($utf8) — the project path holds Æ, and a child under the C locale receives it as ??therion"

    let level_rows = (open --raw ($gate_dir | path join "levels.txt") | lines | where {|l| $l =~ "^[0-9]+ " } | where {|l| ($l | split row " " | first | into int) <= $level })
    let names = (if $level > 0 { $level_rows | each {|l| $l | split row " " | get 1 | split row "," } | flatten } else { $only | split row "," | where {|n| $n != ""} })
    let chosen = (if ($names | is-empty) { $STAGES } else { $STAGES | where {|s| $s.name in $names } })
    let results = ($chosen | par-each --keep-order {|s| let t0 = (date now); let r = (run-one $s); $r | merge {ms: ((((date now) - $t0) / 1ms) | into int)} })

    for r in $results {
        print $"--- ($r.name)"
        print $"TIME ($r.name) ($r.ms)"
        print $"CODE ($r.name) ($r.code)"
        print $r.out
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
