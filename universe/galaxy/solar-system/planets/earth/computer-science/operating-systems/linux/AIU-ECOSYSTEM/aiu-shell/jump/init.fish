if command -sq aiu-shell-jump
    aiu-shell-jump init fish | source
else
    echo 'aiu-shell-jump: command not found, please install it from https://github.com/ajeetdsouza/zoxide'
end
