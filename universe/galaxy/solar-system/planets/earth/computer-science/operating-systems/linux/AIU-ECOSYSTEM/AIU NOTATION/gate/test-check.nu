#!/usr/bin/env nu
# One job: the test check -- runs every gate/tests/*-test.rkt in one Racket process.
# Registered in plan/package-tree.org; gate stage "run-tests".

use ./env.nu *

# main finds the test files, runs them through test-runner.rkt and exits with its code.
def main [] {
    let files = (glob $"($gate_dir)/tests/*-test.rkt" | sort)
    if ($files | is-empty) {
        print "NOTHING-TO-CHECK run-tests: no test files exist yet"
        exit 0
    }
    let res = (with-env {LC_ALL: "C.UTF-8"} { run-external (racket_bin) $"($gate_dir)/test-runner.rkt" ...$files | complete })
    print ($res.stdout | str trim)
    if ($res.stderr | str trim) != "" {
        print ($res.stderr | str trim)
    }
    exit $res.exit_code
}
