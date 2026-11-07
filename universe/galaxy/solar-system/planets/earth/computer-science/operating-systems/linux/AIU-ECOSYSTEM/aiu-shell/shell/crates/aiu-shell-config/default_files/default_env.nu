# Default Nushell Environment Config File
# These "sensible defaults" are set before the user's `env.nu` is loaded
#
# version = "0.116.2"

$env.PROMPT_COMMAND = {||
    let columns = (do -i { (term size).columns } | default 100)
    let dir = match (do -i { $env.PWD | path relative-to $nu.home-dir }) {
        null => $env.PWD
        "" => "~"
        $relative_pwd => (["~" $relative_pwd] | path join)
    }
    let result = (do -i { ^git status --porcelain=v1 --branch | complete })
    let lines = if ($result != null) and ($result.exit_code == 0) { $result.stdout | lines } else { [] }
    let git_text = if ($lines | is-empty) {
        ""
    } else {
        let branch = ($lines | first | str replace "## " "" | split row "..." | first | split row " " | first)
        let changed = ($lines | skip 1 | length)
        let state = if $changed == 0 { "clean" } else { $"($changed) changed" }
        $"($branch)  ($state)"
    }
    let clock = (date now | format date "%H:%M")
    let right = ([$git_text $clock] | where {|part| $part != ""} | str join "  ")
    let tail = $"┤ ($right) ├─"
    let tail_size = ($tail | str length --grapheme-clusters)
    let room = ([8 ($columns - $tail_size - 10)] | math max)
    let dir_size = ($dir | str length --grapheme-clusters)
    let start = ($dir_size - $room + 1)
    let dir_shown = if $dir_size > $room { $"…($dir | str substring --grapheme-clusters $start..)" } else { $dir }
    let head = $"╭─┤ ($dir_shown) ├"
    let head_size = ($head | str length --grapheme-clusters)
    let tail_shown = if ($head_size + $tail_size + 2) < $columns { $tail } else { "" }
    let tail_shown_size = ($tail_shown | str length --grapheme-clusters)
    let fill = ([0 ($columns - $head_size - $tail_shown_size - 1)] | math max)
    let rule = (0..<$fill | each {|step| "─"} | str join)
    $"($head)($rule)($tail_shown)╮(char newline)"
}

$env.PROMPT_COMMAND_RIGHT = {|| "│" }

$env.AIU_START = 0

$env.config = ($env.config
    | upsert render_right_prompt_on_last_line true
    | upsert hooks.pre_execution [{||
        let columns = (do -i { (term size).columns } | default 100)
        $env.AIU_START = (date now | into int)
        let bottom_fill = ([0 ($columns - 2)] | math max)
        let bottom_rule = (0..<$bottom_fill | each {|step| "─"} | str join)
        let head = "╭─┤ output ├"
        let head_size = ($head | str length --grapheme-clusters)
        let fill = ([0 ($columns - $head_size - 1)] | math max)
        let rule = (0..<$fill | each {|step| "─"} | str join)
        print $"╰($bottom_rule)╯"
        print $"($head)($rule)╮"
    }]
    | upsert hooks.pre_prompt [{||
        let started = ($env.AIU_START? | default 0)
        if $started > 0 {
            let columns = (do -i { (term size).columns } | default 100)
            let milliseconds = ((((date now | into int) - $started) / 1000000) | math round)
            let code = ($env.LAST_EXIT_CODE? | default 0)
            let head = $"╰─┤ exit ($code)  ($milliseconds)ms ├"
            let head_size = ($head | str length --grapheme-clusters)
            let fill = ([0 ($columns - $head_size - 1)] | math max)
            let rule = (0..<$fill | each {|step| "─"} | str join)
            print $"($head)($rule)╯"
            $env.AIU_START = 0
        }
    }])

$env.PROMPT_INDICATOR = "│ "
$env.PROMPT_INDICATOR_VI_INSERT = "│ "
$env.PROMPT_INDICATOR_VI_NORMAL = "│ "
$env.PROMPT_MULTILINE_INDICATOR = "│ "
