#!/usr/bin/env nu

use ./env.nu *

const REQUIRED_MAJOR = 0
const REQUIRED_MINOR = 116

def main [] {
    let version = (nu --version | str trim)
    let parts = ($version | split row ".")
    let major = ($parts | get -o 0 | into int)
    let minor = ($parts | get -o 1 | into int)

    if $major != $REQUIRED_MAJOR or $minor != $REQUIRED_MINOR {
        print $"NEED-NU exit 3: this gate needs Nu ($REQUIRED_MAJOR).($REQUIRED_MINOR); this machine has ($version)"
        print "NEED-NU: install nothing here — record it for the laptop list and say so"
        exit 3
    }

    print $"NEED-NU ok: Nu ($version), the pinned version, nothing fetched"
}