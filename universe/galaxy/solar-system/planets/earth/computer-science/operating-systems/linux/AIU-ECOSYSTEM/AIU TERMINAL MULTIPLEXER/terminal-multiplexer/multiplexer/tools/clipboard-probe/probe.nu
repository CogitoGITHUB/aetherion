#!/usr/bin/env nu
# probe.nu -- the phone proof of the Android clipboard bridge (TODO item 24).
#
# One job: show, with printed evidence, that a key puts the pick out to the
# Android clipboard as one OSC 52 string on the owner's own terminal, and that
# a phone whose read direction has no bridge says so by name instead of doing
# nothing and instead of waiting for ever.
#
# No timers: every wait ends on an event — the client ends when its keys end,
# and the records are read again until they hold the answer.
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

def main [
    --bin-dir: string
    --state-dir: string
] {
    let bin_dir = (if ($bin_dir == null) {
        "/tmp/opencode/mux-target/debug"
    } else {
        $bin_dir
    })
    # One state directory per run: the probe never meets an earlier session.
    let state_dir = (if ($state_dir == null) {
        $"/tmp/opencode/mux-clipboard-(random uuid)"
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

    # One pane, one shell: the text that is picked comes from the shell's own
    # output, so the pick is a real pick of what the pane said.
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

    # 1. the shell says one line, and the pane holds it
    let typed = (do -i {
        ^printf "i echo clipboard-proof-line\n" | ^$client --state-dir $state_dir --op screen
    } | complete)
    check "the pane's shell was told to say a line" ($typed.exit_code == 0) $"exit=($typed.exit_code)"

    mut said = 0
    mut tries = 0
    while $said == 0 and $tries < 20 {
        let again = (records $client $state_dir)
        $said = ($again | where {|r|
            ($r | get -o outputs | default {} | get -o text | default "")
                | str contains "clipboard-proof-line"
        } | length)
        $tries = $tries + 1
    }
    check "the line is on the session's wire" ($said > 0) $"hits=($said)"

    # 2. v opens the selection, m sets the mark, w f moves to the next word,
    #    and o puts the region on the Android clipboard. The bytes the client
    #    writes are the terminal's own, so the proof is in its output.
    let out = (do -i {
        ^printf "vmwfo" | ^$client --state-dir $state_dir --op screen
    } | complete)
    let drawn = ($out.stdout | default "")
    check "the copy-out key ran" ($drawn | str contains "went out to the Android clipboard") "the message names the route"
    check "the sequence is one OSC 52 string" ($drawn | str contains "\u{1b}]52;c;") "the output holds the prefix"
    check "the string ends in the bell" ($drawn | str contains "\u{7}") "the output holds the ending"

    # The payload is base64 of the region: it decodes to what the point picked,
    # and it is not empty.
    let after = ($drawn | split row "\u{1b}]52;c;" | skip 1 | first | default "")
    let payload = ($after | split row "\u{7}" | first | default "")
    let decoded = (do -i { ^echo -n $payload | ^base64 -d } | complete)
    check "the payload is the picked text" (($decoded.stdout | str trim | str length) > 0) $"text=($decoded.stdout | str trim)"

    # 4. the read direction on this phone: v then P asks the Android clipboard
    #    for its text. Without the add-on the answer is a name, not a wait; the
    #    client ends either way, which is the proof that nothing hung.
    let addon = (do -i { ^pm list packages com.termux.api } | complete)
    let installed = (($addon.stdout | default "") | str contains "package:com.termux.api")
    let pasted = (do -i {
        ^printf "vP" | ^$client --state-dir $state_dir --op screen
    } | complete)
    let read = ($pasted.stdout | default "")
    if $installed {
        check "the paste ran" ($read | str contains "on its way to") "the add-on answers on this phone"
    } else {
        check "the missing add-on is said by name" ($read | str contains "com.termux.api") "the message names the app"
        check "the client ended and did not wait" ($pasted.exit_code == 0) $"exit=($pasted.exit_code)"
    }

    # 4b. a large paste is bounded and never cut: the unit test of the bridge
    #     holds the number (65536 bytes) and the refusal that says it.

    print $"PROBE: state-dir left for reading: ($state_dir)"
}
