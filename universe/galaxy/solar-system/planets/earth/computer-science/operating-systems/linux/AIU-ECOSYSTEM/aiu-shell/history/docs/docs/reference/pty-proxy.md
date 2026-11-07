# pty-proxy

aiu-shell-history pty-proxy is an experimental lightweight PTY proxy, providing new features without needing to replace your existing terminal or shell. It currently supports bash, zsh, fish, and nu.

!!! Note "Previously `aiu-shell-history hex`"

    `aiu-shell-history pty-proxy` is a replacement for the old `aiu-shell-history hex` command. `aiu-shell-history hex` still works for backward compatibility reasons, but will eventually be removed.

## TUI Rendering

The search TUI exposes a tradeoff: the UI is either in fullscreen alt-screen mode that takes over your terminal, or inline mode that clears your previous output. Neither is great.

With pty-proxy, the aiu-shell-history popup renders over the top of your previous output, but when it's closed we can restore the output successfully.

## Initialization

aiu-shell-history pty-proxy needs to be initialized separately from your existing aiu-shell-history config. Place the init line shown below in your shell's init script, as high in the document as possible, _before_ your normal `aiu-shell-history init` call.

=== "zsh"

    ```shell
    eval "$(aiu-shell-history pty-proxy init zsh)"
    ```

=== "bash"

    ```shell
    eval "$(aiu-shell-history pty-proxy init bash)"
    ```

=== "fish"

    Add

    ```shell
    aiu-shell-history pty-proxy init fish | source
    ```

    to your `is-interactive` block in your `~/.config/fish/config.fish` file

=== "Nushell"

    Run in *Nushell*:

    ```shell
    mkdir ~/.local/share/aiu-shell-history/
    aiu-shell-history pty-proxy init nu | save -f ~/.local/share/aiu-shell-history/pty-proxy-init.nu
    ```

    Add to `config.nu`, **before** the regular `aiu-shell-history init`:

    ```shell
    source ~/.local/share/aiu-shell-history/pty-proxy-init.nu
    ```
    Nushell's `source` command requires a static file path, so you must
    pre-generate the file.

---

If the `aiu-shell-history` binary is not in your `PATH` by default, you should initialize pty-proxy as soon as it is set. For example, for a bash user with aiu-shell-history installed in `~/.aiu-shell-history/bin/aiu-shell-history`, a config file might look like this:

```bash
export PATH=$HOME/.aiu-shell-history/bin:$PATH
eval "$(aiu-shell-history pty-proxy init bash)"

# ... other shell configuration ...

eval "$(aiu-shell-history init bash)"
```
