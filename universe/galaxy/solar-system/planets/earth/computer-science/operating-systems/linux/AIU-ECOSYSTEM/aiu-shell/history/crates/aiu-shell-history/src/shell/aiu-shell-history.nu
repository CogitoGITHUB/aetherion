# Source this in your ~/.config/nushell/config.nu
# minimum supported version = 0.93.0
module compat {
  export def --wrapped "random uuid -v 7" [...rest] { aiu-shell-history uuid }
}
use (if not (
    (version).major > 0 or
    (version).minor >= 103
) { "compat" }) *

if 'AIU_SHELL_HISTORY_SESSION' not-in $env or ('AIU_SHELL_HISTORY_SHLVL' not-in $env) or ($env.AIU_SHELL_HISTORY_SHLVL != ($env.SHLVL? | default "")) {
    $env.AIU_SHELL_HISTORY_SESSION = (random uuid -v 7 | str replace -a "-" "")
    $env.AIU_SHELL_HISTORY_SHLVL = ($env.SHLVL? | default "")
}
hide-env -i AIU_SHELL_HISTORY_HISTORY_ID

def _aiu_shell_history_osc133_command_executed [] {
    if 'AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE' not-in $env {
        return
    }
    if 'AIU_SHELL_HISTORY_HISTORY_ID' not-in $env or ($env.AIU_SHELL_HISTORY_HISTORY_ID | is-empty) {
        return
    }

    print -n $"(char -u '1b')]133;C(char bel)"
}

def _aiu_shell_history_osc133_command_finished [exit_code: int] {
    if 'AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE' not-in $env {
        return
    }
    if 'AIU_SHELL_HISTORY_HISTORY_ID' not-in $env or ($env.AIU_SHELL_HISTORY_HISTORY_ID | is-empty) {
        return
    }

    print -n $"(char -u '1b')]133;D;($exit_code);history_id=($env.AIU_SHELL_HISTORY_HISTORY_ID);session_id=($env.AIU_SHELL_HISTORY_SESSION)(char bel)"
}

# Magic token to make sure we don't record commands run by keybindings
let AIU_SHELL_HISTORY_KEYBINDING_TOKEN = $"# (random uuid)"

let _aiu_shell_history_pre_execution = {||
    if ($nu | get history-enabled?) == false {
        return
    }
    let cmd = (commandline)
    if ($cmd | is-empty) {
        return
    }
    if not ($cmd | str starts-with $AIU_SHELL_HISTORY_KEYBINDING_TOKEN) {
        $env.AIU_SHELL_HISTORY_HISTORY_ID = (aiu-shell-history history start -- $cmd | complete | get stdout | str trim)
        _aiu_shell_history_osc133_command_executed
    }
}

let _aiu_shell_history_pre_prompt = {||
    let last_exit = $env.LAST_EXIT_CODE
    if 'AIU_SHELL_HISTORY_HISTORY_ID' not-in $env {
        return
    }
    _aiu_shell_history_osc133_command_finished $last_exit
    with-env { AIU_SHELL_HISTORY_LOG: error } {
        if (version).minor >= 104 or (version).major > 0 {
            job spawn {
                ^aiu-shell-history history end $'--exit=($env.LAST_EXIT_CODE)' -- $env.AIU_SHELL_HISTORY_HISTORY_ID | complete
            } | ignore
        } else {
            do { aiu-shell-history history end $'--exit=($last_exit)' -- $env.AIU_SHELL_HISTORY_HISTORY_ID } | complete
        }

    }
    hide-env -i AIU_SHELL_HISTORY_HISTORY_ID
}

def _aiu_shell_history_search_cmd [...flags: string] {
    if (version).minor >= 106 or (version).major > 0 {
        [
            $AIU_SHELL_HISTORY_KEYBINDING_TOKEN,
            ([
                `with-env { AIU_SHELL_HISTORY_LOG: error, AIU_SHELL_HISTORY_QUERY: (commandline), AIU_SHELL_HISTORY_SHELL: nu } {`,
                    ([
                        'let output = (run-external aiu-shell-history search',
                        ($flags | append [--interactive] | each {|e| $'"($e)"'}),
                        'e>| str trim)',
                    ] | flatten | str join ' '),
                    'if ($output | str starts-with "__aiu_shell_history_accept__:") {',
                    'commandline edit --accept ($output | str replace "__aiu_shell_history_accept__:" "")',
                    '} else {',
                    'commandline edit $output',
                    '}',
                `}`,
            ] | flatten | str join "\n"),
        ]
    } else {
        [
            $AIU_SHELL_HISTORY_KEYBINDING_TOKEN,
            ([
                `with-env { AIU_SHELL_HISTORY_LOG: error, AIU_SHELL_HISTORY_QUERY: (commandline) } {`,
                    'commandline edit',
                    '(run-external aiu-shell-history search',
                        ($flags | append [--interactive] | each {|e| $'"($e)"'}),
                    ' e>| str trim)',
                `}`,
            ] | flatten | str join ' '),
        ]
    } | str join "\n"
}

$env.config = ($env | default {} config).config
$env.config = ($env.config | default {} hooks)
$env.config = (
    $env.config | upsert hooks (
        $env.config.hooks
        | upsert pre_execution (
            $env.config.hooks | get pre_execution? | default [] | append $_aiu_shell_history_pre_execution)
        | upsert pre_prompt (
            $env.config.hooks | get pre_prompt? | default [] | append $_aiu_shell_history_pre_prompt)
    )
)

$env.config = ($env.config | default [] keybindings)
