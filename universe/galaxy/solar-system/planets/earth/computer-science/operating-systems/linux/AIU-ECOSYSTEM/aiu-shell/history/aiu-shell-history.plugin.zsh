# shellcheck disable=2148,SC2168,SC1090,SC2125
local FOUND_AIU_SHELL_HISTORY=$+commands[aiu-shell-history]

if [[ $FOUND_AIU_SHELL_HISTORY -eq 1 ]]; then
  source <(aiu-shell-history init zsh)
fi
