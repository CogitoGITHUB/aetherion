if not set -q AIU_SHELL_HISTORY_SESSION; or test "$AIU_SHELL_HISTORY_SHLVL" != "$SHLVL"
    set -gx AIU_SHELL_HISTORY_SESSION (aiu-shell-history uuid)
    set -gx AIU_SHELL_HISTORY_SHLVL $SHLVL
end
set --erase AIU_SHELL_HISTORY_HISTORY_ID

function _aiu_shell_history_osc133_command_executed
    set -q AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE; or return
    test -n "$AIU_SHELL_HISTORY_HISTORY_ID"; or return

    printf '\033]133;C\a'
end

function _aiu_shell_history_osc133_command_finished --argument-names exit_code
    set -q AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE; or return
    test -n "$AIU_SHELL_HISTORY_HISTORY_ID"; or return

    printf '\033]133;D;%s;history_id=%s;session_id=%s\a' "$exit_code" "$AIU_SHELL_HISTORY_HISTORY_ID" "$AIU_SHELL_HISTORY_SESSION"
end

function _aiu_shell_history_preexec --on-event fish_preexec
    if not test -n "$fish_private_mode"
        set -g AIU_SHELL_HISTORY_HISTORY_ID (aiu-shell-history history start -- "$argv[1]" 2>/dev/null)
        _aiu_shell_history_osc133_command_executed
    end
end

function _aiu_shell_history_postexec --on-event fish_postexec
    set -l s $status

    if test -n "$AIU_SHELL_HISTORY_HISTORY_ID"
        _aiu_shell_history_osc133_command_finished $s
        AIU_SHELL_HISTORY_LOG=error aiu-shell-history history end --exit $s -- $AIU_SHELL_HISTORY_HISTORY_ID &>/dev/null &
        disown
    end

    set --erase AIU_SHELL_HISTORY_HISTORY_ID
end

# Check if tmux popup is available (tmux >= 3.2)
function _aiu_shell_history_tmux_popup_check
    if not test -n "$TMUX"
        echo 0
        return
    end

    if test "$AIU_SHELL_HISTORY_TMUX_POPUP" = false
        echo 0
        return
    end

    set -l tmux_version (tmux -V 2>/dev/null | string match -r '\d+\.\d+')
    if not test -n "$tmux_version"
        echo 0
        return
    end

    set -l parts (string split '.' $tmux_version)
    set -l m1 $parts[1]
    set -l m2 0
    if test (count $parts) -ge 2
        set m2 $parts[2]
    end

    if not string match -rq '^[0-9]+$' -- "$m1"
        echo 0
        return
    end

    if not string match -rq '^[0-9]+$' -- "$m2"
        set m2 0
    end

    if test "$m1" -gt 3 2>/dev/null; or begin
            test "$m1" -eq 3 2>/dev/null; and test "$m2" -ge 2 2>/dev/null
        end
        echo 1
    else
        echo 0
    end
end

function _aiu_shell_history_search
    set -l keymap_mode
    switch $fish_key_bindings
        case fish_vi_key_bindings fish_hybrid_key_bindings
            switch $fish_bind_mode
                case default
                    set keymap_mode vim-normal
                case insert
                    set keymap_mode vim-insert
            end
        case '*'
            set keymap_mode emacs
    end

    set -l use_tmux_popup (_aiu_shell_history_tmux_popup_check)

    set -l AIU_SHELL_HISTORY_H
    set -l AIU_SHELL_HISTORY_STATUS 0
    if test "$use_tmux_popup" -eq 1
        set -l tmpdir (mktemp -d)
        if not test -d "$tmpdir"
            # if mktemp got errors
            set AIU_SHELL_HISTORY_H (AIU_SHELL_HISTORY_SHELL=fish AIU_SHELL_HISTORY_LOG=error AIU_SHELL_HISTORY_QUERY=(commandline -b) aiu-shell-history search --keymap-mode=$keymap_mode $argv -i 3>&1 1>&2 2>&3 3>&- | string collect)
            set AIU_SHELL_HISTORY_STATUS $pipestatus[1]
        else
            set -l result_file "$tmpdir/result"

            set -l query (commandline -b | string replace -a "'" "'\\''")
            set -l escaped_args ""
            for arg in $argv
                set escaped_args "$escaped_args '"(string replace -a "'" "'\\''" -- $arg)"'"
            end

            # In the popup, aiu-shell-history goes to terminal, stderr goes to file
            set -l cdir (pwd)
            # Keep default value anyways
            set -l popup_width (test -n "$AIU_SHELL_HISTORY_TMUX_POPUP_WIDTH" && echo "$AIU_SHELL_HISTORY_TMUX_POPUP_WIDTH" || echo "80%")
            set -l popup_height (test -n "$AIU_SHELL_HISTORY_TMUX_POPUP_HEIGHT" && echo "$AIU_SHELL_HISTORY_TMUX_POPUP_HEIGHT" || echo "60%")
            tmux display-popup -d "$cdir" -w "$popup_width" -h "$popup_height" -E -E -- \
                sh -c "PATH='$PATH' AIU_SHELL_HISTORY_SESSION='$AIU_SHELL_HISTORY_SESSION' AIU_SHELL_HISTORY_SHELL=fish AIU_SHELL_HISTORY_LOG=error AIU_SHELL_HISTORY_QUERY='$query' aiu-shell-history search --keymap-mode=$keymap_mode$escaped_args -i 2>'$result_file'"
            set AIU_SHELL_HISTORY_STATUS $status

            if test -f "$result_file"
                set AIU_SHELL_HISTORY_H (cat "$result_file" | string collect)
            end

            command rm -rf "$tmpdir"
        end
    else
        # In fish 3.4 and above we can use `"$(some command)"` to keep multiple lines separate;
        # but to support fish 3.3 we need to use `(some command | string collect)`.
        # https://fishshell.com/docs/current/relnotes.html#id24 (fish 3.4 "Notable improvements and fixes")
        set AIU_SHELL_HISTORY_H (AIU_SHELL_HISTORY_SHELL=fish AIU_SHELL_HISTORY_LOG=error AIU_SHELL_HISTORY_QUERY=(commandline -b) aiu-shell-history search --keymap-mode=$keymap_mode $argv -i 3>&1 1>&2 2>&3 3>&- | string collect)
        set AIU_SHELL_HISTORY_STATUS $pipestatus[1]
    end

    if test "$AIU_SHELL_HISTORY_STATUS" -ne 0
        test -n "$AIU_SHELL_HISTORY_H"; and printf '%s\n' "$AIU_SHELL_HISTORY_H" >&2
        commandline -f repaint
        return "$AIU_SHELL_HISTORY_STATUS"
    end

    set AIU_SHELL_HISTORY_H (string trim -- $AIU_SHELL_HISTORY_H | string collect) # trim whitespace

    if test -n "$AIU_SHELL_HISTORY_H"
        if string match --quiet '__aiu_shell_history_accept__:*' "$AIU_SHELL_HISTORY_H"
            set -l AIU_SHELL_HISTORY_HIST (string replace "__aiu_shell_history_accept__:" "" -- "$AIU_SHELL_HISTORY_H" | string collect)
            commandline -r "$AIU_SHELL_HISTORY_HIST"
            commandline -f repaint
            commandline -f execute
            return
        else
            commandline -r "$AIU_SHELL_HISTORY_H"
        end
    end

    commandline -f repaint
end

function _aiu_shell_history_bind_up
    # Fallback to fish's builtin up-or-search if we're in search or paging mode
    if commandline --search-mode; or commandline --paging-mode
        up-or-search
        return
    end

    # Only invoke aiu-shell-history if we're on the top line of the command
    set -l lineno (commandline --line)

    switch $lineno
        case 1
            _aiu_shell_history_search --shell-up-key-binding
        case '*'
            up-or-search
    end
end
