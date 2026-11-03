#!/usr/bin/env nu

use ./env.nu *

const AREAS = ["errors" "narration" "machine" "security" "join" "devloop" "journal" "buffer" "notation" "plugins" "commands" "checkpoint" "routes" "input" "drawing" "models" "dashboard" "send" "picker" "audit" "entry"]

def area_index [name] {
    let found = ($AREAS | enumerate | where {|a| $a.item == $name })
    if ($found | is-empty) { 99 } else { $found | first | get index }
}

def clean-text [text] {
    let no_blocks = ($text | str replace --all --regex '(?s)#\|.*?\|#' ' ')
    $no_blocks | lines | each {|line|
        let trimmed = ($line | str trim)
        if ($trimmed | str starts-with ";") {
            null
        } else {
            $line | str replace --regex ';;.*$' ''
        }
    } | where {|l| $l != null }
}

def require-paths [text] {
    let flat = ($text | str join " ")
    let forms = (try { $flat | parse --regex '(?s)\(require((?:[^()]|\([^()]*\))*)\)' | get -o capture0 } catch {|e| [] })
    $forms | each {|form|
        let paths = (try { $form | parse --regex '"([^"]+)"' | get -o capture0 } catch {|e| [] })
        $paths | where {|p| ($p | str ends-with ".rkt") }
    } | flatten
}

def area-of [file] {
    let rel = ($file | path relative-to $package_src)
    $rel | split row "/" | first
}

def target-area [file required] {
    let dir = ($file | path dirname)
    let absolute = ($dir | path join $required | path expand)
    let rel = (try { $absolute | path relative-to $package_src } catch {|e| null })
    if ($rel == null) { null } else { $rel | split row "/" | first }
}

def main [] {
    let files = (glob $"($package_src)/**/*.rkt") | lines
    let file_count = ($files | length)

    if ($file_count == 0) {
        print "NOTHING-TO-CHECK one-way — no Racket files exist under editor yet"
        exit 0
    }

    let pairs = ($files | each {|p|
        let from = (area-of $p)
        let paths = (require-paths (clean-text (open --raw $p)))
        $paths | each {|q|
            let to = (target-area $p $q)
            let up = (if ($to == null) { true } else { (area_index $to) > (area_index $from) })
            {from: $from, to: $to, path: $q, file: $p, up: $up}
        }
    } | flatten)

    let pair_count = ($pairs | length)

    if ($pair_count == 0) {
        print $"NOTHING-TO-CHECK one-way — ($file_count) files scanned, none requires another area yet"
        exit 0
    }

    let bad = ($pairs | where {|e| $e.up })
    let bad_count = ($bad | length)

    if ($bad_count == 0) {
        print $"OK one-way — ($pair_count) requires checked in ($file_count) files, all point downward"
        exit 0
    }

    for b in $bad {
        let rel = ($b.file | path relative-to $package_src)
        let from = $b.from
        let to = (if ($b.to == null) { "outside the package" } else { $b.to })
        let path = $b.path
        print $"ONE-WAY — ($rel) requires ($path); from area ($from) to ($to); a require may only point downward"
    }
    print $"ONE-WAY — ($bad_count) upward requires in ($file_count) files"
    exit 1
}
