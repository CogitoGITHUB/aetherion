#!/usr/bin/env nu

use ./env.nu *

def in_join [p] {
    ($p | path relative-to $project_root) =~ "join/"
}

def rust_crossings [rs] {
    $rs | each {|p|
        let text = open --raw $p
        if ($text | str contains ".rkt") {
            if (in_join $p) { null } else { {path: $p, why: "a Rust file names a .rkt file"} }
        } else { null }
    } | where {|e| $e != null }
}

def racket_crossings [rkt] {
    $rkt | each {|p|
        let text = open --raw $p
        if ($text | str contains ".rs") {
            {path: $p, why: "a Racket file names a .rs file"}
        } else { null }
    } | where {|e| $e != null }
}

def main [] {
    let rs = (glob $"($package_dir)/**/*.rs") | lines
    let rkt = (glob $"($package_dir)/**/*.rkt") | lines
    let checked = ($rs | length) + ($rkt | length)

    if ($checked == 0) {
        print "NOTHING-TO-CHECK language-split — no source files exist under editor/ yet"
        exit 0
    }

    let bad = (rust_crossings $rs | append (racket_crossings $rkt))
    let bad_count = ($bad | length)

    if ($bad_count == 0) {
        print $"OK language-split — ($checked) files checked, no Rust/Racket crossing outside join/"
        exit 0
    }

    for b in $bad {
        let rel = ($b.path | path relative-to $project_root)
        let why = $b.why
        print $"LANGUAGE-SPLIT — ($rel): ($why); only join/ may cross"
    }
    print $"LANGUAGE-SPLIT — ($bad_count) crossings outside join/ in ($checked) files"
    exit 1
}