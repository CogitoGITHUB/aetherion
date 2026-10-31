#!/usr/bin/env nu
# probe.nu -- the phone proof of the session commands (TODO item 49).
#
# One job: show, with printed evidence, that the owner can list the sessions,
# create one, rename this one, switch the client to another, and kill one — and
# that a killed session is gone for good while a session cannot kill itself.

def check [label: string, ok: bool, detail: string] {
    if $ok {
        print $"PROBE: OK ($label) ($detail)"
    } else {
        print $"PROBE: FAIL ($label) ($detail)"
    }
}

# records answers the records of one session, read through the client.
def records [client: string, state_dir: string] {
    let read = (do -i { ^$client --state-dir $state_dir --op read --since 0 } | complete)
    ($read.stdout | split row (char newline) | where {|line| ($line | str trim) != "" }
        | each {|line| $line | from json })
}

# says answers the last record with one `what`, or an empty record.
def says [client: string, state_dir: string, what: string] {
    let held = (records $client $state_dir)
    ($held | where {|r| ($r | get -o what | default "") == $what } | last | default {})
}

def main [--bin-dir: string, --root: string] {
    let bin_dir = (if ($bin_dir == null) { "/tmp/opencode/mux-target/debug" } else { $bin_dir })
    let root = (if ($root == null) { $"/tmp/opencode/mux-sessions-(random uuid)" } else { $root })
    let holder = ($bin_dir | path join "holder")
    let client = ($bin_dir | path join "client")
    let first = ($root | path join "first")

    print $"PROBE: holder=($holder)"
    print $"PROBE: client=($client)"
    print $"PROBE: root=($root)"

    rm -rf $root
    mkdir $root

    job spawn {
        try { do { ^$holder --state-dir $first --sessions-dir $root } } catch { |why| null }
    }
    mut tries = 0
    while (not (($first | path join "holder.sock") | path exists)) and $tries < 200 {
        $tries = $tries + 1
    }
    check "the first session stands" ((($first | path join "holder.sock") | path exists)) "its socket is there"

    # 1. the listing says what stands
    # Every command below is the owner's own path: the command line of a screen,
    # which is the line an agent's words run too.
    ^printf ':sessions\r' | ^$client --state-dir $first --op screen | ignore
    let list = (says $client $first "the sessions were listed" | get -o outputs | default {})
    let one = (($list | get -o sessions | default []) | where {|s| $s.session == "first" } | first | default {})
    check "the listing names the session" (($one | get -o session | default "") == "first") $"sessions=($list.sessions | length)"
    check "the listing says a holder holds it" (($one | get -o held | default false) == true) "held"

    # 2. create a second session: its holder is started, and it stands on its own
    ^printf ':session create second\r' | ^$client --state-dir $first --op screen | ignore
    let second = ($root | path join "second")
    mut waits = 0
    while (not (($second | path join "holder.sock") | path exists)) and $waits < 200 {
        $waits = $waits + 1
    }
    check "a second session stands" (((($second | path join "holder.sock")) | path exists)) "its socket is there"
    check "the creation is a record" ((says $client $first "a session was created" | get -o outputs | default {} | get -o session | default "") == "second") "the record says which"

    # 3. the listing holds both
    ^printf ':sessions\r' | ^$client --state-dir $first --op screen | ignore
    let names = ((says $client $first "the sessions were listed" | get -o outputs | default {}
        | get -o sessions | default []) | each {|s| $s.session })
    check "the listing holds both sessions" (($names | length) == 2) $"names=($names | to json -r)"

    # 4. switch: this client moves to the other session's socket, without a new
    #    client and without anyone touching the terminal
    let moved = (do -i {
        ^printf ':session switch second\r' | ^$client --state-dir $first --op screen
    } | complete)
    let said = ($moved.stderr | default "")
    check "the client switched to the other session" ($said | str contains "switching to the session at") $"stderr=($said | lines | last)"
    check "the switch ended cleanly" ($moved.exit_code == 0) $"exit=($moved.exit_code)"

    # 5. kill: the other session is asked to shut down, and it removes its own
    #    socket, pid and log. What is left of it is nothing.
    ^printf ':session kill second\r' | ^$client --state-dir $first --op screen | ignore
    let killed = (says $client $first "a session was killed" | get -o outputs | default {})
    check "the kill is a record" (($killed | get -o session | default "") == "second") "the record says which"
    let gone = (not (($second | path join "holder.sock") | path exists)) and (not (($second | path join "events.log") | path exists))
    check "the killed session is gone for good" $gone "its socket and its log are removed"
    ^printf ':sessions\r' | ^$client --state-dir $first --op screen | ignore
    let after = ((says $client $first "the sessions were listed" | get -o outputs | default {} | get -o sessions | default [])
        | where {|s| $s.session == "second" } | first | default {})
    check "the listing says no holder holds it" (($after | get -o held | default true) == false) $"held=($after | get -o held | default "gone")"


    # 6. a session cannot kill itself, and it says so by name
    ^printf ':session kill first\r' | ^$client --state-dir $first --op screen | ignore
    let refused = (says $client $first "the session was not killed" | get -o result | default {})
    check "a session cannot kill itself" (($refused | get -o why | default "") | str contains "cannot remove the ground") $"why=($refused | get -o why | default "" | str substring 0..60)"
    check "the first session still stands" ((($first | path join "holder.sock") | path exists)) "its socket is there"

    print $"PROBE: root left for reading: ($root)"
}
