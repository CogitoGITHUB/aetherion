if (( $+commands[aiu-shell-jump] )); then
  eval "$(aiu-shell-jump init zsh)"
else
  echo 'aiu-shell-jump: command not found, please install it from https://github.com/ajeetdsouza/zoxide'
fi
