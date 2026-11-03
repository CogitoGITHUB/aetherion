#!/usr/bin/env nu
# aiumux -- the one command that starts or joins the multiplexer.
# One job: make "one command" true -- build the two binaries when the source is
# newer than they are, start the holder when no holder holds the session, and
# put the screen on the terminal. Without this, joining a session means typing a
# build, a state directory, a sessions directory and an op by hand.
#
#   aiumux                  join the session named main, starting it if it is down
#   aiumux NAME             the same for the session called NAME
#   aiumux ls               the sessions that stand, and which one a holder holds
#   aiumux kill [NAME]      end that session's holder; the session's files stay
#   aiumux --start          start the session and stop: no screen, an agent can drive it
#   aiumux --rebuild        build the binaries again, then do what was asked
#
# The state root is the one the MCP registration in OpenCode already names:
#   ~/.local/state/aiu-multiplexer/target    the binaries
#   ~/.local/state/aiu-multiplexer/sessions  one directory per session
# --state-root DIR moves it, so a session made to try something cannot be
# mistaken for the owner's own.
#
# Every wait here is an event: the client waits for the holder's socket with a
# filesystem watch, and this script never sleeps and never polls. A start that
# fails names the file to read, and does it before the screen takes the terminal.

# script_dir is this file's directory: tools/, one level under the project.
const script_dir = path self | path dirname

# package_dir is where cargo runs: the crate lives beside tools/.
const package_dir = $script_dir | path dirname | path join "multiplexer"

# check-name answers whether a name can be a session's, in the holder's own
# words (holder/sessions.rs, check_name): one path segment, no slash, no
# dot-dot, nothing a shell would read as an option.
def check-name [name: string] {
    if ($name | is-empty) {
        return "a session needs a name: aiumux NAME"
    }
    if ($name | str contains "/") {
        return $"a session's name is one path segment, and ($name) holds a slash"
    }
    if $name == "." or $name == ".." {
        return $"a session's name cannot be ($name)"
    }
    if ($name | str starts-with "-") {
        return $"a session's name cannot start with a dash, and ($name) does"
    }
    ""
}

# stale answers whether anything in the crate is newer than the binaries, so a
# change to the source is never left behind a binary built yesterday. The
# answer comes from the filesystem: no clock is read for a decision.
def stale [package: string, target_dir: string] {
    let holder = ($target_dir | path join "debug" | path join "holder")
    if not ($holder | path exists) { return true }
    let sources = (glob $"($package)/src/**/*.rs") | append ($package | path join "Cargo.toml")
    let there = ($sources | where {|f| $f | path exists })
    if ($there | is-empty) { return false }
    let built = (ls $holder | get modified | first)
    let newest = ($there | each {|f| ls $f } | flatten | get modified | math max)
    $newest > $built
}

# build answers after building the two binaries, or stops with the reason by
# name. On this phone this is the slow step, and the script says so first and
# then says nothing until cargo has something to say.
def build [target_dir: string, why: string] {
    print $"aiumux: ($why) -- building into ($target_dir)"
    print "aiumux: this is the slow step on this phone; it says nothing until cargo does"
    let built = (with-env {CARGO_TARGET_DIR: $target_dir} {
        do -i { ^cargo build --offline --manifest-path ($package_dir | path join "Cargo.toml") }
        | complete
    })
    if $built.exit_code != 0 {
        print $"aiumux: the build failed, so nothing was started -- rc=($built.exit_code)"
        print ($built.stderr | str trim)
        exit 3
    }
    print "aiumux: the two binaries are built"
}

# alive answers whether a process with this pid is running: signal 0 asks the
# kernel without touching the process.
def alive [pid: string] {
    if ($pid | is-empty) { return false }
    let asked = (do -i { ^kill -0 $pid } | complete)
    $asked.exit_code == 0
}

# holds answers whether a holder holds the session in this directory: the pid
# file names a process still running, and the socket is there beside it. A
# socket left by a holder that was killed is not a holder.
def holds [dir: string] {
    let pid_file = ($dir | path join "holder.pid")
    let sock = ($dir | path join "holder.sock")
    if not ($pid_file | path exists) { return false }
    if not ($sock | path exists) { return false }
    alive (open --raw $pid_file | str trim)
}

# start runs one holder with no screen of its own, in a session of its own, so
# it outlives this script and every client that joins it later. setsid and
# nohup are what make it survive the terminal that started it; the holder's own
# words go to holder.out, and that path is printed before anything else.
def start [holder: string, dir: string, sessions: string, shell: string] {
    let out = ($dir | path join "holder.out")
    let head = $"exec setsid nohup '($holder)' --state-dir '($dir)'"
    let tail = $"--sessions-dir '($sessions)' --shell '($shell)' > '($out)' 2>&1 < /dev/null &"
    let asked = (^bash -c $"($head) ($tail)" | complete)
    if $asked.exit_code != 0 {
        print $"aiumux: the holder could not be started -- rc=($asked.exit_code)"
        print ($asked.stderr | str trim)
        exit 3
    }
    print $"aiumux: the holder was asked to start for ($dir | path basename)"
    print $"aiumux: its own words are in ($out); a holder that refuses says so there, by name"
}

def main [
    --rebuild (-b)             # build the binaries again, even when they are current
    --start (-s)               # start the holder and stop: no screen of this terminal
    --state-root (-r): string  # where the sessions and the binaries stand
    ...args: string            # ls | kill [NAME] | NAME
] {
    let root = (if ($state_root | is-empty) {
        $env.HOME | path join ".local" | path join "state" | path join "aiu-multiplexer"
    } else {
        $state_root
    })
    let target_dir = ($root | path join "target")
    let sessions = ($root | path join "sessions")
    let bin_dir = ($target_dir | path join "debug")
    let holder = ($bin_dir | path join "holder")
    let client = ($bin_dir | path join "client")

    let what = ($args | get -o 0 | default "main")
    let rest = ($args | skip 1)

    # ls and kill name no session of their own when the owner means all of
    # them: they read the sessions directory and build nothing.
    if $what == "ls" {
        if not ($sessions | path exists) {
            print $"aiumux: no session stands yet -- ($sessions) holds nothing"
            return
        }
        let names = (ls $sessions | where type == dir | get name
            | each {|p| $p | path basename } | sort)
        if ($names | is-empty) {
            print $"aiumux: no session stands yet -- ($sessions) holds no session"
            return
        }
        for name in $names {
            let dir = ($sessions | path join $name)
            let state = (if (holds $dir) { "held" } else { "no holder" })
            print $"($name)\t($state)"
        }
        return
    }

    if $what == "kill" {
        let name = ($rest | get -o 0 | default "main")
        let why = (check-name $name)
        if ($why | str length) > 0 {
            print $"aiumux: ($why)"
            exit 2
        }
        let dir = ($sessions | path join $name)
        if not (holds $dir) {
            print $"aiumux: no holder holds ($name), so there is nothing to end"
            exit 2
        }
        let pid = (open --raw ($dir | path join "holder.pid") | str trim)
        let asked = (do -i { ^kill -TERM $pid } | complete)
        if $asked.exit_code != 0 {
            print $"aiumux: the holder ($pid) could not be ended -- rc=($asked.exit_code)"
            exit 3
        }
        print $"aiumux: the holder ($pid) of ($name) was asked to end; its files stay in ($dir)"
        return
    }

    let name = $what
    let why = (check-name $name)
    if ($why | str length) > 0 {
        print $"aiumux: ($why)"
        exit 2
    }

    if $rebuild {
        build $target_dir "the owner asked for a rebuild"
    } else if (stale $package_dir $target_dir) {
        build $target_dir "the source is newer than the binaries, or the binaries are not there"
    }

    let dir = ($sessions | path join $name)
    mkdir $dir
    if (holds $dir) {
        print $"aiumux: a holder already holds ($name)"
    } else {
        start $holder $dir $sessions "/bin/sh"
    }

    if $start {
        print $"aiumux: ($name) stands for any client or agent; `aiumux ($name)` puts a screen on it"
        return
    }

    # The client waits for the socket itself, on the filesystem event that
    # creates it, so the screen is the next thing after this line either way.
    exec $client --state-dir $dir --op screen
}
