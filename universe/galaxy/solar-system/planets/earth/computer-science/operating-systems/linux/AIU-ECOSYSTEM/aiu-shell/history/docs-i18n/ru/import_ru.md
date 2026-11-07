# `aiu-shell-history import`

aiu-shell-history может импортировать историю из "старого" файла истории

`aiu-shell-history import auto` предпринимает попытку определить тип командного интерфейса
(через \$SHELL) и запускает нужный скрипт импорта.

К сожалению, эти файлы содержат не так много информации, как aiu-shell-history, так что не 
все функции будут доступны с импортированными данными.

# zsh

```
aiu-shell-history import zsh
```

Если у вас есть HISTFILE, то эта команда должна сработать. Иначе, попробуйте

```
HISTFILE=/path/to/history/file aiu-shell-history import zsh
```

Этот параметр поддерживает как и упрощённый, так и полный формат.

# bash

TODO
