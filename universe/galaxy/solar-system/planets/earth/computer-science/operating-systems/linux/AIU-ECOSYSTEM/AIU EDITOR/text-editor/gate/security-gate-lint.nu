#!/usr/bin/env nu

use ./env.nu *

def security_dir [] {
    $package_src | path join "security"
}

def predicate_names [files] {
    $files | each {|p|
        open --raw $p | lines | where {|l| ($l | str trim) | str starts-with "(define (" } | each {|l|
            let inside = $l | str replace --regex '^\(define \(' ''
            let name = $inside | str trim | split row " " | first
            {name: $name, file: $p}
        }
    } | flatten
}

def callers_of [name files] {
    $files | where {|p| (open --raw $p | str contains "(name ") }
}

def main [] {
    let dir = security_dir

    if (($dir | path exists) == false) {
        print "NOTHING-TO-CHECK security-gate — the security area does not exist yet"
        exit 0
    }

    let rule_files = ((glob $"($dir)/**/*.rkt") | lines)
    if ($rule_files | is-empty) {
        print "NOTHING-TO-CHECK security-gate — the security area holds no rule file yet"
        exit 0
    }

    let all_racket = ((glob $"($package_src)/**/*.rkt") | lines)
    let predicates = predicate_names $rule_files

    if ($predicates | is-empty) {
        print "NOTHING-TO-CHECK security-gate — the security area defines no predicate yet"
        exit 0
    }

    let uncalled = ($predicates | where {|p|
        let outside = ($all_racket | where {|f| ($f | path dirname) != $dir })
        (callers_of $p.name $outside | is-empty)
    })

    for p in $predicates {
        let outside = ($all_racket | where {|f| ($f | path dirname) != $dir })
        let who = (callers_of $p.name $outside | each {|f| $f | path relative-to $project_root })
        if ($who | is-empty) {
            print $"CALLER ($p.name) — no file calls it yet"
        } else {
            print $"CALLER ($p.name) — called by ($who | str join ', ')"
        }
    }

    let bad = ($uncalled | length)
    if $bad == 0 {
        print $"OK security-gate — ($predicates | length) predicates, every one is called"
        exit 0
    }
    print $"SECURITY-GATE — ($bad) of ($predicates | length) predicates have no caller"
    exit 1
}
