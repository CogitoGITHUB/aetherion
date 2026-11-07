# Key binding

По умолчанию, aiu-shell-history будет переназначать <kbd>Ctrl-r</kbd> и клавишу 'стрелка вверх'.
Если вы не хотите этого, установите параметр AIU_SHELL_HISTORY_NOBIND прежде чем вызывать `aiu-shell-history init`

Например,

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init zsh)"
```

Таким образом вы можете разрешить переназначение клавиш aiu-shell-history, если это необходимо.
Делайте это до инициализирующего вызова.

# zsh

aiu-shell-history устанавливает виджет ZLE "aiu-shell-history-search"

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init zsh)"

bindkey '^r' aiu-shell-history-search

# зависит от режима терминала
bindkey '^[[A' aiu-shell-history-search
bindkey '^[OA' aiu-shell-history-search
```

# bash

```
export AIU_SHELL_HISTORY_NOBIND="true"
eval "$(aiu-shell-history init bash)"

# Переопределите  ctrl-r, и любые другие сочетания горячих клавиш тут
bind -x '"\C-r": __aiu_shell_history_history'
```
