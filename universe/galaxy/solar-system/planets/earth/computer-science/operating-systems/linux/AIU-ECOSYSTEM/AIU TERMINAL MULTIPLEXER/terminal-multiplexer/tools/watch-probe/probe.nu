#!/usr/bin/env nu
# probe.nu -- the phone proof of the read-only watch attach (TODO item 60).
#
# One job: show, with printed evidence, that a watcher draws the session and
# says it is watching, that its keys change nothing, and that letting it go
# leaves the session as it was — a screen still types into the same pane.
#
# The holder's own refusals of a watcher's send and control are the proof of
# =tests/watch.rs=: the watcher's connection is the holder's to police, and
# the test speaks the wire itself. This probe is the client's half.

def check [label: string, ok: bool, detail: string] {
    if $ok {
        print $"PROBE: OK ($label) ($detail)"
    } else {
        print $"PROBE: FAIL ($label) ($detail)"
    }
}

def main [--bin-dir: string, --state-dir: string] {
    let bin_dir = (if ($bin_dir == null) {
        "/tmp/opencode/mux-target/debug"
    } else {
        $bin_dir
    })
    let state_dir = (if ($state_dir == null) {
        $"/tmp/opencode/mux-watch-(random uuid)"
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

    job spawn {
        try {
            do { ^$holder --state-dir $state_dir } | save --force ($state_dir | path join "holder.out")
        } catch { |why| null }
    }

    # 1. the watcher: it draws the session, and its keys change nothing. The
    #    key it tries to send is a command a shell would run, so if a byte
    #    reached the pane the pane would say so.
    let watched = (do -i {
        ^printf "i echo a-watcher-changed-this\n" | ^$client --state-dir $state_dir --op watch
    } | complete)
    let drawn = ($watched.stdout | default "")
    check "the watcher draws" ($drawn | str contains "main") "the pane's name is on the drawing"
    check "the watcher says it watches" ($drawn | str contains "WATCH/") "the mode row names the role"
    check "the watcher says the rule" ($drawn | str contains "cannot change it") "the message names it"
    check "the watcher ended cleanly" ($watched.exit_code == 0) $"exit=($watched.exit_code)"

    # 2. the keys changed nothing: the record the shell would have made (the
    #    pane was given a command) is not there, and the pane's own output does
    #    not hold the words.
    let log = ($state_dir | path join "events.log")
    let said = (open --raw $log)
    check "no key reached the pane" (not ($said | str contains "a-watcher-changed-this")) "the words are nowhere in the log"

    # 3. the watcher's leaving is a record, and the session goes on.
    let detached = ($said | str contains "the client detached")
    check "the watcher's leaving is a record" $detached "the detach is in the journal"

    # 4. the session was not touched: a screen still types in the same pane and
    #    the shell answers.
    let held = (do -i {
        ^printf "i echo from-the-screen-pane\n" | ^$client --state-dir $state_dir --op screen
    } | complete)
    mut waits = 0
    while (not ((open --raw $log) | str contains "from-the-screen-pane")) and $waits < 400 {
        $waits = $waits + 1
    }
    let after = (open --raw $log)
    check "the screen still reaches the shell" ($after | str contains "from-the-screen-pane") "the shell's own words are in the log"
    check "the screen's keys went through" ($held.exit_code == 0) $"exit=($held.exit_code)"

    print $"PROBE: state-dir left for reading: ($state_dir)"
}
