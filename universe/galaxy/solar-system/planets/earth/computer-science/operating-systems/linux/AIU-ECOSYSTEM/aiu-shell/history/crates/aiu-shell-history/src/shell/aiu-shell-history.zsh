# shellcheck disable=SC2034,SC2153,SC2086,SC2155

# Above line is because shellcheck doesn't support zsh, per
# https://github.com/koalaman/shellcheck/wiki/SC1071, and the ignore: param in
# ludeeus/action-shellcheck only supports _directories_, not _files_. So
# instead, we manually add any error the shellcheck step finds in the file to
# the above line ...

# Source this in your ~/.zshrc
autoload -U add-zsh-hook

zmodload zsh/datetime 2>/dev/null

# If zsh-autosuggestions is installed, configure it to use aiu-shell-history's search. If
# you'd like to override this, then add your config after the $(aiu-shell-history init zsh)
# in your .zshrc
_zsh_autosuggest_strategy_aiu_shell_history() {
    # silence errors, since we don't want to spam the terminal prompt while typing.
    # '$all-user' is a literal aiu-shell-history author filter, not a shell variable
    # shellcheck disable=SC2016
    suggestion=$(AIU_SHELL_HISTORY_QUERY="$1" aiu-shell-history search --cmd-only --author '$all-user' --limit 1 --search-mode prefix 2>/dev/null)
}

if [ -n "${ZSH_AUTOSUGGEST_STRATEGY:-}" ]; then
    ZSH_AUTOSUGGEST_STRATEGY=("aiu-shell-history" "${ZSH_AUTOSUGGEST_STRATEGY[@]}")
else
    ZSH_AUTOSUGGEST_STRATEGY=("aiu-shell-history")
fi

if [[ -z "${AIU_SHELL_HISTORY_SESSION:-}" || "${AIU_SHELL_HISTORY_SHLVL:-}" != "$SHLVL" ]]; then
    export AIU_SHELL_HISTORY_SESSION=$(aiu-shell-history uuid)
    export AIU_SHELL_HISTORY_SHLVL=$SHLVL
fi
AIU_SHELL_HISTORY_HISTORY_ID=""

__aiu_shell_history_osc133_command_executed() {
    [[ -n "${AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE:-}" ]] || return
    [[ -n "${AIU_SHELL_HISTORY_HISTORY_ID:-}" ]] || return

    printf '\033]133;C\a'
}

__aiu_shell_history_osc133_command_finished() {
    [[ -n "${AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE:-}" ]] || return
    [[ -n "${AIU_SHELL_HISTORY_HISTORY_ID:-}" ]] || return

    printf '\033]133;D;%s;history_id=%s;session_id=%s\a' "$1" "$AIU_SHELL_HISTORY_HISTORY_ID" "${AIU_SHELL_HISTORY_SESSION:-}"
}

__aiu_shell_history_osc133_prompt_start=$'%{\033]133;A;cl=line\a%}'
__aiu_shell_history_osc133_prompt_end=$'%{\033]133;B\a%}'

__aiu_shell_history_osc133_wrap_prompt() {
    local __aiu_shell_history_prompt="${PROMPT-}"
    local __aiu_shell_history_rprompt="${RPROMPT-}"

    __aiu_shell_history_prompt="${__aiu_shell_history_prompt//$__aiu_shell_history_osc133_prompt_start/}"
    __aiu_shell_history_prompt="${__aiu_shell_history_prompt//$__aiu_shell_history_osc133_prompt_end/}"
    __aiu_shell_history_rprompt="${__aiu_shell_history_rprompt//$__aiu_shell_history_osc133_prompt_start/}"
    __aiu_shell_history_rprompt="${__aiu_shell_history_rprompt//$__aiu_shell_history_osc133_prompt_end/}"

    if [[ -n "${AIU_SHELL_HISTORY_PTY_PROXY_ACTIVE:-}" ]]; then
        PROMPT="${__aiu_shell_history_osc133_prompt_start}${__aiu_shell_history_prompt}"
        RPROMPT="${__aiu_shell_history_rprompt}${__aiu_shell_history_osc133_prompt_end}"
    else
        PROMPT="$__aiu_shell_history_prompt"
        RPROMPT="$__aiu_shell_history_rprompt"
    fi
}

_aiu_shell_history_preexec() {
    local id
    id=$(aiu-shell-history history start -- "$1" 2>/dev/null)
    export AIU_SHELL_HISTORY_HISTORY_ID="$id"
    __aiu_shell_history_osc133_command_executed
    __aiu_shell_history_preexec_time=${EPOCHREALTIME-}
}

_aiu_shell_history_precmd() {
    local EXIT="$?" __aiu_shell_history_precmd_time=${EPOCHREALTIME-}

    __aiu_shell_history_osc133_wrap_prompt

    [[ -z "${AIU_SHELL_HISTORY_HISTORY_ID:-}" ]] && return

    local duration=""
    if [[ -n $__aiu_shell_history_preexec_time && -n $__aiu_shell_history_precmd_time ]]; then
        printf -v duration %.0f $(((__aiu_shell_history_precmd_time - __aiu_shell_history_preexec_time) * 1000000000))
    fi

    __aiu_shell_history_osc133_command_finished "$EXIT"
    (AIU_SHELL_HISTORY_LOG=error aiu-shell-history history end --exit $EXIT ${duration:+--duration=$duration} -- $AIU_SHELL_HISTORY_HISTORY_ID &) >/dev/null 2>&1
    export AIU_SHELL_HISTORY_HISTORY_ID=""
}

# Check if tmux popup is available (tmux >= 3.2)
__aiu_shell_history_tmux_popup_check() {
    [[ -n "${TMUX-}" ]] || return 1
    [[ "${AIU_SHELL_HISTORY_TMUX_POPUP:-true}" != "false" ]] || return 1

    # https://github.com/tmux/tmux/wiki/FAQ#how-often-is-tmux-released-what-is-the-version-number-scheme
    local tmux_version
    tmux_version=$(tmux -V 2>/dev/null | sed -n 's/^[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p') # Could have used grep...
    [[ -z "$tmux_version" ]] && return 1

    local m1 m2
    m1=${tmux_version%%.*}
    m2=${tmux_version#*.}
    m2=${m2%%.*}
    [[ "$m1" =~ ^[0-9]+$ ]] || return 1
    [[ "$m2" =~ ^[0-9]+$ ]] || m2=0
    (( m1 > 3 || (m1 == 3 && m2 >= 2) ))
}

# Use global variable to fix scope issues with traps
__aiu_shell_history_popup_tmpdir=""
__aiu_shell_history_tmux_popup_cleanup() {
    [[ -n "$__aiu_shell_history_popup_tmpdir" && -d "$__aiu_shell_history_popup_tmpdir" ]] && command rm -rf "$__aiu_shell_history_popup_tmpdir"
    __aiu_shell_history_popup_tmpdir=""
}

__aiu_shell_history_search_cmd() {
    local -a search_args=("$@")

    if __aiu_shell_history_tmux_popup_check; then
        __aiu_shell_history_popup_tmpdir=$(mktemp -d) || return 1
        local result_file="$__aiu_shell_history_popup_tmpdir/result"

        trap '__aiu_shell_history_tmux_popup_cleanup' EXIT HUP INT TERM

        local escaped_query escaped_args
        escaped_query=$(printf '%s' "$BUFFER" | sed "s/'/'\\\\''/g")
        escaped_args=""
        for arg in "${search_args[@]}"; do
            escaped_args+=" '$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")'"
        done

        # In the popup, aiu-shell-history goes to terminal, stderr goes to file
        local cdir popup_width popup_height
        cdir=$(pwd)
        popup_width="${AIU_SHELL_HISTORY_TMUX_POPUP_WIDTH:-80%}" # Keep default value anyways
        popup_height="${AIU_SHELL_HISTORY_TMUX_POPUP_HEIGHT:-60%}"
        tmux display-popup -d "$cdir" -w "$popup_width" -h "$popup_height" -E -E -- \
            sh -c "PATH='$PATH' AIU_SHELL_HISTORY_SESSION='$AIU_SHELL_HISTORY_SESSION' AIU_SHELL_HISTORY_SHELL=zsh AIU_SHELL_HISTORY_LOG=error AIU_SHELL_HISTORY_QUERY='$escaped_query' aiu-shell-history search $escaped_args -i 2>'$result_file'"

        if [[ -f "$result_file" ]]; then
            cat "$result_file"
        fi

        __aiu_shell_history_tmux_popup_cleanup
        trap - EXIT HUP INT TERM
    else
        AIU_SHELL_HISTORY_SHELL=zsh AIU_SHELL_HISTORY_LOG=error AIU_SHELL_HISTORY_QUERY=$BUFFER aiu-shell-history search "${search_args[@]}" -i 3>&1 1>&2 2>&3 3>&-
    fi
}

_aiu_shell_history_search() {
    emulate -L zsh
    zle -I

    # swap stderr and stdout, so that the tui stuff works
    # TODO: not this
    local output __aiu_shell_history_status
    # shellcheck disable=SC2048
    output=$(__aiu_shell_history_search_cmd $*)
    __aiu_shell_history_status=$?

    zle reset-prompt
    # re-enable bracketed paste
    # shellcheck disable=SC2154
    echo -n ${zle_bracketed_paste[1]} >/dev/tty

    if (( __aiu_shell_history_status != 0 )); then
        [[ -n $output ]] && print -r -- "$output" >/dev/tty
        return $__aiu_shell_history_status
    fi

    if [[ -n $output ]]; then
        RBUFFER=""
        LBUFFER=$output

        if [[ $LBUFFER == __aiu_shell_history_accept__:* ]]
        then
            LBUFFER=${LBUFFER#__aiu_shell_history_accept__:}
            zle accept-line
        fi
    fi
}
_aiu_shell_history_search_vicmd() {
    _aiu_shell_history_search --keymap-mode=vim-normal
}
_aiu_shell_history_search_viins() {
    _aiu_shell_history_search --keymap-mode=vim-insert
}

_aiu_shell_history_up_search() {
    # Only trigger if the buffer is a single line
    if [[ ! $BUFFER == *$'\n'* ]]; then
        _aiu_shell_history_search --shell-up-key-binding "$@"
    else
        zle up-line
    fi
}
_aiu_shell_history_up_search_vicmd() {
    _aiu_shell_history_up_search --keymap-mode=vim-normal
}
_aiu_shell_history_up_search_viins() {
    _aiu_shell_history_up_search --keymap-mode=vim-insert
}

add-zsh-hook preexec _aiu_shell_history_preexec
add-zsh-hook precmd _aiu_shell_history_precmd

zle -N aiu-shell-history-search _aiu_shell_history_search
zle -N aiu-shell-history-search-vicmd _aiu_shell_history_search_vicmd
zle -N aiu-shell-history-search-viins _aiu_shell_history_search_viins
zle -N aiu-shell-history-up-search _aiu_shell_history_up_search
zle -N aiu-shell-history-up-search-vicmd _aiu_shell_history_up_search_vicmd
zle -N aiu-shell-history-up-search-viins _aiu_shell_history_up_search_viins

# These are compatibility widget names for "aiu-shell-history <= 17.2.1" users.
zle -N _aiu_shell_history_search_widget _aiu_shell_history_search
zle -N _aiu_shell_history_up_search_widget _aiu_shell_history_up_search
