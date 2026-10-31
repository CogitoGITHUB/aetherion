#!/usr/bin/env nu
# probe.nu -- the phone proof of the journal's rules (TODO item 51).
#
# One job: show, with printed evidence, that a session's log stays inside the
# bound that is written down, that the trim is a record of its own and keeps the
# newest records whole, and that every file of the session is the owner's alone.
#
# No timers: every wait ends on an event — the client ends when its work is
# done, and the log is read again until the trim record is there.
#
# The binaries live outside the tree: the build writes into CARGO_TARGET_DIR.
# One place to change them: --bin-dir.

def check [label: string, ok: bool, detail: string] {
    if $ok {
        print $"PROBE: OK ($label) ($detail)"
    } else {
        print $"PROBE: FAIL ($label) ($detail)"
    }
}

# records answers the records of the session, read through the client.
def records [client: string, state_dir: string] {
    let read = (do -i { ^$client --state-dir $state_dir --op read --since 0 } | complete)
    ($read.stdout | split row (char newline) | where {|line| ($line | str trim) != "" }
        | each {|line| $line | from json })
}

# mode answers the permission bits of one path, as three octal digits.
def mode [path: string] {
    (^stat -c %a $path | str trim)
}

def main [
    --bin-dir: string
    --state-dir: string
    --limit: int
] {
    let bin_dir = (if ($bin_dir == null) {
        "/tmp/opencode/mux-target/debug"
    } else {
        $bin_dir
    })
    # The bound the probe runs under: small enough that a few seconds of a
    # pane's words pass it, and the same rule the session keeps, only lower.
    let limit = (if ($limit == null) { 8000 } else { $limit })
    let state_dir = (if ($state_dir == null) {
        $"/tmp/opencode/mux-journal-(random uuid)"
    } else {
        $state_dir
    })
    let holder = ($bin_dir | path join "holder")
    let client = ($bin_dir | path join "client")

    print $"PROBE: holder=($holder)"
    print $"PROBE: client=($client)"
    print $"PROBE: state-dir=($state_dir)"
    print $"PROBE: limit=($limit)"

    rm -rf $state_dir
    mkdir $state_dir

    let layout = {
        "direction": "row"
        "panes": [
            { "name": "work", "tab": "main", "program": "/bin/sh", "weight": 1, "cols": 80, "rows": 24 }
        ]
    } | to json | save --force ($state_dir | path join "layout.json")

    job spawn {
        try {
            do {
                ^$holder --state-dir $state_dir --layout ($state_dir | path join "layout.json") --log-limit $limit
            }
            | save --force ($state_dir | path join "holder.out")
        } catch { |why| null }
    }

    # 1. the session's own files are the owner's alone
    check "the state directory is 0700" ((mode $state_dir) == "700") $"mode=(mode $state_dir)"
    check "the log is 0600" ((mode ($state_dir | path join "events.log")) == "600") $"mode=(mode ($state_dir | path join "events.log"))"
    check "the socket is in a directory only the owner may enter" ((mode $state_dir) == "700") "the socket's own mode does not matter inside it"

    # 2. the pane says a line often enough to pass the bound
    mut at = 0
    mut sends = 0
    while $at < 40 {
        let said = (do -i {
            ^$client --state-dir $state_dir --op send --pane work --data "echo a-journal-line-of-some-length\n" --count 1
        } | complete)
        if $said.exit_code == 0 { $sends = $sends + 1 }
        $at = $at + 1
    }
    check "the sends reached the pane" ($sends > 0) $"sends=($sends)"

    # 3. the trim happened, and it said so in a record of its own. The wait
    #    ends on the records arriving, never on a clock.
    mut trimmed = 0
    mut tries = 0
    mut held = []
    while $trimmed == 0 and $tries < 20 {
        $held = (records $client $state_dir)
        $trimmed = ($held | where {|r| ($r | get -o what | default "") == "the journal was trimmed" } | length)
        $tries = $tries + 1
    }
    check "the journal was trimmed" ($trimmed > 0) $"records=($trimmed)"
    let last = ($held | where {|r| ($r | get -o what | default "") == "the journal was trimmed" } | last)
    let kept = ($last | get -o outputs | default {} | get -o kept | default 0)
    let dropped = ($last | get -o outputs | default {} | get -o from-seq | default 0)
    check "the trim says what it kept and what it let go" (($kept > 0) and ($dropped > 1)) $"kept=($kept) from-seq=($dropped)"
    check "the trim record is in the log itself" (($held | where {|r| ($r | get -o what | default "") == "the journal was trimmed" } | length) > 0) "read back through the client"

    # 4. the rule holds on the file: size, whole lines, no half record, no file
    #    left beside it
    let path = ($state_dir | path join "events.log")
    let size = (^stat -c %s $path | str trim | into int)
    check "the log is inside the bound" ($size <= $limit) $"size=($size) limit=($limit)"
    let body = (open --raw $path)
    let lines = ($body | lines | where {|line| ($line | str trim) != "" })
    let bad = ($lines | where {|line| (do -i { $line | from json | ignore; false } catch { true }) } | length)
    check "every line of the log is a whole record" ($bad == 0) $"lines=($lines | length) bad=($bad)"
    check "the last record is whole" ($body | str ends-with (char newline)) "the file ends on a newline"
    check "no half-written file is left beside the log" (((($state_dir | path join "events.log.new") | path exists)) == false) "the sibling is gone"

    # 5. what the trim let go is not silently missing: reading from zero stops at
    #    the first kept record, and the trim record says which seq that is.
    let first_kept = ($lines | first | from json | get seq)
    check "the log starts at the record the trim kept" ($first_kept == ($last | get -o outputs | default {} | get -o from-seq | default 0)) $"first=($first_kept)"

    print $"PROBE: state-dir left for reading: ($state_dir)"
    print $"PROBE: log bytes=($size) limit=($limit) lines=($lines | length)"
}
