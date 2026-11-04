#!/usr/bin/env nu
# probe.nu -- the phone proof of the rewind (TODO item 59).
#
# One job: show, with printed evidence, that the owner chooses a record and the
# pane shows the text as it stood at that record, read from the journal, and
# that looking back changes nothing: the live pane keeps its own output and its
# shell is not restarted.
#
# No timers: every wait ends on an event — the client ends when its keys end,
# and the records are read again until the line is there.
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

# state answers the holder's state record, so the panes and their shells can be
# read without a screen.
def state [client: string, state_dir: string] {
    let read = (do -i { ^$client --state-dir $state_dir --op state } | complete)
    ($read.stdout | lines | where {|line| ($line | str trim) != "" } | last | from json)
}

def main [
    --bin-dir: string
    --state-dir: string
] {
    let bin_dir = (if ($bin_dir == null) {
        "/tmp/opencode/mux-target/debug"
    } else {
        $bin_dir
    })
    let state_dir = (if ($state_dir == null) {
        $"/tmp/opencode/mux-rewind-(random uuid)"
    } else {
        $state_dir
    })
    let holder = ($bin_dir | path join "holder")
    let client = ($bin_dir | path join "client")

    print $"PROBE: holder=($holder)"
    print $"PROBE: client=($client)"
    print $"PROBE: state-dir=($state_dir)"

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
                ^$holder --state-dir $state_dir --layout ($state_dir | path join "layout.json")
            }
            | save --force ($state_dir | path join "holder.out")
        } catch { |why| null }
    }

    # 1. the pane says two lines, one after the other, so there is a record
    #    between them to choose.
    let first = (do -i {
        ^printf "i echo the-first-line\n" | ^$client --state-dir $state_dir --op screen
    } | complete)
    mut said = 0
    mut tries = 0
    while $said == 0 and $tries < 20 {
        $said = ((records $client $state_dir) | where {|r|
            ($r | get -o outputs | default {} | get -o text | default "") | str contains "the-first-line"
        } | length)
        $tries = $tries + 1
    }
    check "the pane said the first line" ($said > 0) $"records=($said)"

    let second = (do -i {
        ^printf "i echo the-second-line\n" | ^$client --state-dir $state_dir --op screen
    } | complete)
    mut said_two = 0
    mut tries_two = 0
    while $said_two == 0 and $tries_two < 20 {
        $said_two = ((records $client $state_dir) | where {|r|
            ($r | get -o outputs | default {} | get -o text | default "") | str contains "the-second-line"
        } | length)
        $tries_two = $tries_two + 1
    }
    check "the pane said the second line" ($said_two > 0) $"records=($said_two)"

    # 2. the record to go back to: the one that carried the first line. Its seq
    #    is the number the owner names.
    let held = (records $client $state_dir)
    let at = ($held | where {|r|
        ($r | get -o outputs | default {} | get -o text | default "") | str contains "the-first-line"
    } | last | get seq)
    check "the record of the first line has a number" (($at | describe) == "int") $"seq=($at)"

    let before = (state $client $state_dir)
    let pid_before = ($before | get -o outputs | default {} | get -o panes | default [] | first | get -o pid | default 0)
    check "the shell is running before the look back" ($pid_before > 0) $"pid=($pid_before)"

    # 3. the owner chooses the record on the command line: `:rewind work SEQ`.
    #    The screen asks the holder, and the panel shows the journal's own lines.
    let keys = $":rewind work ($at)\r"
    let looked = (do -i {
        ^printf $keys | ^$client --state-dir $state_dir --op screen
    } | complete)
    let drawn = ($looked.stdout | default "")
    check "the rewind panel is drawn" ($drawn | str contains "the rewind — work at record") "the panel holds its title"
    check "the panel says the journal is the source" ($drawn | str contains "the live pane is not changed") "the panel says it"
    check "the panel shows the line as it stood" ($drawn | str contains "the-first-line") "the journal's line is drawn"

    # 4. the answer is the journal's own text up to that record, and never a
    #    line recorded after it.
    let after = (records $client $state_dir)
    let back = ($after | where {|r| ($r | get -o what | default "") == "the pane was read back" })
    check "the look back is a record of its own" (($back | length) > 0) $"records=($back | length)"
    let answer = ($back | last | get -o outputs | default {})
    let lines = ($answer | get -o lines | default [])
    check "it answers the pane's lines up to the record" (($lines | length) > 0) $"lines=($lines | length)"
    check "it answers what the pane had said and no more" (($lines | any {|line| $line | str contains "the-first-line" }) and (($lines | any {|line| $line | str contains "the-second-line" }) == false)) $"lines=($lines | to json -r)"

    # 5. looking back changed nothing: the same shell, and the live pane still
    #    holds both lines.
    let later = (state $client $state_dir)
    let pid_after = ($later | get -o outputs | default {} | get -o panes | default [] | first | get -o pid | default 0)
    check "the shell was not restarted" ($pid_after == $pid_before) $"pid=($pid_after)"
    let live = ($later | get -o outputs | default {} | get -o panes | default [] | first | get -o text | default "")
    check "the live pane still holds both lines" ((($live | str contains "the-first-line")) and (($live | str contains "the-second-line"))) $"live=($live | str length) bytes"
    check "the live pane still takes keys" ((do -i {
        ^$client --state-dir $state_dir --op send --pane work --data "echo still-alive\n" --count 1
    } | complete).exit_code == 0) "a send after the look back went through"

    print $"PROBE: state-dir left for reading: ($state_dir)"
}
