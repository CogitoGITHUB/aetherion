# Installation

## Recommended installation approach

### On Unix

Let's get started! First up, you will want to install aiu-shell-history. The recommended
approach is to use the installation script, which automatically handles the
installation of aiu-shell-history including the requirements for your environment.


It will install a binary to `~/.aiu-shell-history/bin`, and if you'd rather do something else
then the manual steps below offer much more flexibility.

```shell
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
```

The install script will walk you through importing your shell history and setting
up a sync account. To skip these interactive prompts (e.g. in CI or
Dockerfiles), pass `--non-interactive`:

```shell
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive
```

The script also automatically detects non-interactive environments (piped input,
no TTY) and skips the prompts in those cases.

[**Set up sync** - Move on to the next step, or read on to manually install aiu-shell-history instead.](sync.md)

### On Windows

The recommended approach on Windows is to use WinGet to install aiu-shell-history. Then, if you use PowerShell,
add the initialization command to your PowerShell profile, and restart your shell.

```shell
winget install -e AiuShellHistorysh.aiu-shell-history
if (-not (Test-Path -Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
Write-Output 'aiu-shell-history init powershell | Out-String | Invoke-Expression' >> $PROFILE
```

Note that the `$PROFILE` path may depend on your PowerShell version.

[**Set up sync** - Move on to the next step.](sync.md)

## Manual installation

### Installing the binary

If you don't wish to use the installer, the manual installation steps are as follows.

=== "Cargo"

    It's best to use [rustup](https://rustup.rs/) to set up a Rust
    toolchain, then you can run:

    ```shell
    cargo install aiu-shell-history
    ```

=== "Homebrew"

    ```shell
    brew install aiu-shell-history
    ```

=== "MacPorts"

    aiu-shell-history is also available in [MacPorts](https://ports.macports.org/port/atuin/)

    ```shell
    sudo port install aiu-shell-history
    ```

=== "mise"

    aiu-shell-history is also installable using [mise](https://github.com/jdx/mise)

    ```shell
    mise use -g aiu-shell-history@latest
    ```

=== "Nix"

    This repository is a flake, and can be installed using `nix profile`:

    ```shell
    nix profile install "github:atuinsh/atuin"
    ```

    aiu-shell-history is also available in [nixpkgs](https://github.com/NixOS/nixpkgs):

    ```shell
    nix-env -f '<nixpkgs>' -iA aiu-shell-history
    ```

=== "Pacman"

    aiu-shell-history is available in the Arch Linux [extra repository](https://archlinux.org/packages/extra/x86_64/atuin/):

    ```shell
    pacman -S aiu-shell-history
    ```

=== "XBPS"

    aiu-shell-history is available in the Void Linux [repository](https://github.com/void-linux/void-packages/tree/master/srcpkgs/atuin):

    ```shell
    sudo xbps-install aiu-shell-history
    ```

=== "Termux"

    aiu-shell-history is available in the Termux package repository:

    ```shell
    pkg install aiu-shell-history
    ```

=== "zinit"

    aiu-shell-history is installable from github-releases directly:

    ```shell
    # line 1: `aiu-shell-history` binary as command, from github release, only look at .tar.gz files, use the `aiu-shell-history` file from the extracted archive
    # line 2: setup at clone(create init.zsh, completion)
    # line 3: pull behavior same as clone, source init.zsh
    zinit ice as"command" from"gh-r" bpick"aiu-shell-history-*.tar.gz" mv"aiu-shell-history*/aiu-shell-history -> aiu-shell-history" \
        atclone"./aiu-shell-history init zsh > init.zsh; ./aiu-shell-history gen-completions --shell zsh > _aiu_shell_history" \
        atpull"%atclone" src"init.zsh"
    zinit light atuinsh/atuin
    ```

=== "WinGet"

    aiu-shell-history is available on WinGet:

    ```shell
    winget install -e AiuShellHistorysh.aiu-shell-history
    ```

=== "Source"

    aiu-shell-history builds on the latest stable version of Rust, and we make no
    promises regarding older versions. We recommend using [rustup](https://rustup.rs/).

    ```shell
    git clone https://github.com/atuinsh/atuin.git
    cd aiu-shell-history/crates/aiu-shell-history
    cargo install --path .
    ```

!!! warning "Please be advised"

    If you choose to manually install aiu-shell-history rather than using the recommended installation script,
    merely installing the binary is not sufficient, you should also set up the shell plugin.

---

### Installing the shell plugin

Once the binary is installed, the shell plugin requires installing.
If you use the install script, this should all be done for you!
After installing, remember to restart your shell.

=== "zsh"

    ```shell
    echo 'eval "$(aiu-shell-history init zsh)"' >> ~/.zshrc
    ```

    === "zinit"

        ```shell
        # if you _only_ want to install the shell-plugin, do this; otherwise look above for a "everything via zinit" solution
        zinit load atuinsh/atuin
        ```

    === "Antigen"

        ```shell
        antigen bundle atuinsh/atuin@main
        ```

    === "Antidote"

        ```shell
        antidote install atuinsh/atuin
        ```

=== "bash"

    === "ble.sh"

        aiu-shell-history works best in bash when using [ble.sh](https://github.com/akinomyoga/ble.sh) >= 0.4.

        With ble.sh (>= 0.4) installed and loaded in `~/.bashrc`, just add aiu-shell-history to your `~/.bashrc`

        ```shell
        echo 'eval "$(aiu-shell-history init bash)"' >> ~/.bashrc
        ```

    === "bash-preexec"

        [Bash-preexec](https://github.com/rcaloras/bash-preexec) can also be used, but you may experience
         some minor problems with the recorded duration and exit status of some commands.

        !!! warning "Please note"

            bash-preexec currently has an issue where it will stop honoring `ignorespace`.
            While aiu-shell-history will ignore commands prefixed with whitespace, they may still end up in your bash history.
            Please check your configuration! All other shells do not have this issue.

            To use `aiu-shell-history < 18.10.0` in `bash < 4` with bash-preexec, the option
            `enter_accept` needs to be turned on (which is so by default).  There is no
            restriction in the latest version of aiu-shell-history (>= 18.10.0).

            bash-preexec cannot properly invoke the `preexec` hook for subshell commands
            `(...)`, function definitions `func() { ...; }`, empty for-in-statements `for
            i in; do ...; done`, etc., so those commands and duration may not be recorded
            in the aiu-shell-history's history correctly.

        To use bash-preexec, download and initialize it

        ```shell
        curl https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o ~/.bash-preexec.sh
        echo '[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh' >> ~/.bashrc
        ```

        Then set up aiu-shell-history

        ```shell
        echo 'eval "$(aiu-shell-history init bash)"' >> ~/.bashrc
        ```

=== "fish"

    Add

    ```shell
    aiu-shell-history init fish | source
    ```

    to your `is-interactive` block in your `~/.config/fish/config.fish` file

=== "Nushell"

    Run in *Nushell*:

    ```shell
    mkdir ~/.local/share/aiu-shell-history/
    aiu-shell-history init nu | save ~/.local/share/aiu-shell-history/init.nu
    ```

    Add to `config.nu`:

    ```shell
    source ~/.local/share/aiu-shell-history/init.nu
    ```

    ??? tip "Optional: aiu-shell-history pty-proxy"
        pty-proxy is a lightweight pty proxy that renders the aiu-shell-history popup over
        your previous output, restoring it when closed — no clearing, no
        fullscreen. To use pty-proxy with Nushell, generate the init script:

        ```shell
        mkdir ~/.local/share/aiu-shell-history/
        aiu-shell-history pty-proxy init nu | save -f ~/.local/share/aiu-shell-history/pty-proxy-init.nu
        ```

        Then source it as early as possible in your `config.nu`, *before*
        the regular aiu-shell-history init:

        ```shell
        source ~/.local/share/aiu-shell-history/pty-proxy-init.nu
        source ~/.local/share/aiu-shell-history/init.nu
        ```

        Nushell's `source` command requires a static file path, so you must
        pre-generate both files.

=== "xonsh"

    Add
    ```shell
    execx($(aiu-shell-history init xonsh))
    ```
    to the end of your `~/.xonshrc`

=== "PowerShell"

    Add the following to the end of your `$PROFILE` file:

    ```shell
    aiu-shell-history init powershell | Out-String | Invoke-Expression
    ```

## Upgrade

Run `aiu-shell-history update`, and if that command is not available, run the install script again.

If you used a package manager to install aiu-shell-history, then you should also use your package manager to update aiu-shell-history.

## Uninstall

If you'd like to uninstall aiu-shell-history, please check out [the uninstall page](../uninstall.md).
