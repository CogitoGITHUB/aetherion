use std/dt [datetime-diff, pretty-print-duration]

# Return the current working directory
@category "default"
export def pwd [
    --physical (-P) # Resolve symbolic links
] {
    if $physical {
        $env.PWD | path expand
    } else {
        $env.PWD
    }
}
