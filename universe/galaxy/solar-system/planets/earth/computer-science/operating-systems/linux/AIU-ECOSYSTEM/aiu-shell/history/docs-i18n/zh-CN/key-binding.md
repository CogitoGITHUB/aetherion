# 键位绑定

默认情况下， aiu-shell-history 将会重新绑定 <kbd>Ctrl-r</kbd> 和 `up` 键。如果你不想使用默认绑定，请在调用 `aiu-shell-history init` 之前设置 AIU_SHELL_HISTORY_NOBIND

例如：

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init zsh)"
```

如果需要，你可以在调用 `aiu-shell-history init` 之后对 aiu-shell-history 重新进行键绑定

# zsh

aiu-shell-history 定义了 ZLE 部件 "aiu-shell-history-search"

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init zsh)"

bindkey '^r' aiu-shell-history-search

# 取决于终端模式
bindkey '^[[A' aiu-shell-history-search
bindkey '^[OA' aiu-shell-history-search
```

# bash

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init bash)"

# 绑定到 ctrl-r, 也可以在这里添加任何其他你想要的绑定方式
bind -x '"\C-r": __aiu_shell_history_history'
```

# fish

```
set -gx AIU_SHELL_HISTORY_NOBIND "true"
aiu-shell-history init fish | source

# 在 normal 和 insert 模式下绑定到 ctrl-r，你也可以在此处添加其他键位绑定
bind \cr _aiu_shell_history_search
bind -M insert \cr _aiu_shell_history_search
```
