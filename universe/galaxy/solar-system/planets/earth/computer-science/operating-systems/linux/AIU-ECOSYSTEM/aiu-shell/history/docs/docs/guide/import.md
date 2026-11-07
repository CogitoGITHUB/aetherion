# Import existing history

aiu-shell-history uses a shell plugin to ensure that we capture new shell history. But for
older history, you will need to import it

This will import the history for your current shell:
```
aiu-shell-history import auto
```

Alternatively, you can specify the shell like so:

```
aiu-shell-history import bash
aiu-shell-history import zsh # etc
```

Your old shell history file will continue to be updated, regardless of aiu-shell-history usage.
