<!-- markdownlint-configure-file {
  "MD013": {
    "code_blocks": false,
    "tables": false
  },
  "MD033": false,
  "MD041": false
} -->

<div align="center">

<sup>Special thanks to:</sup>

<table>
  <tr>
    <td align="center">
      <!-- markdownlint-disable-next-line MD013 -->
      <a href="https://go.warp.dev/zoxide"><img alt="Sponsored by Warp" width="230" src="https://raw.githubusercontent.com/warpdotdev/brand-assets/refs/heads/main/Github/Sponsor/Warp-Github-LG-03.png" /></a>
      <div><sup><b>Warp, built for coding with multiple AI agents.</b></sup></div>
      <div><sup>Available for macOS, Linux, and Windows.</sup></div>
      <div><sup>
        Visit
        <a href="https://go.warp.dev/zoxide"><u>warp.dev</u></a>
        to learn more.
      </sup></div>
    </td>
    <td align="center">
      <!-- markdownlint-disable-next-line MD013 -->
      <a href="https://www.recall.ai/careers?ashby_jid=7b02811e-bc91-4ef2-925d-f56a5acac13b&utm_source=github&utm_medium=sponsorship&utm_campaign=zoxide"><img alt="Sponsored by Recall.ai" width="230" src="https://github.com/user-attachments/assets/0c5cb177-561c-4637-bef6-cf584939c829" /></a>
      <div><sup>Processing over 3TB/s of video at peak load,</sup></div>
      <!-- markdownlint-disable-next-line MD013 -->
      <div><sup>now <a href="https://www.recall.ai/careers?ashby_jid=7b02811e-bc91-4ef2-925d-f56a5acac13b&utm_source=github&utm_medium=sponsorship&utm_campaign=zoxide">hiring in SF.</a></sup></div>
    </td>
  </tr>
</table>

<hr />

# aiu-shell-jump

[![crates.io][crates.io-badge]][crates.io]
[![Downloads][downloads-badge]][releases]
[![Built with Nix][builtwithnix-badge]][builtwithnix]

aiu-shell-jump is a **smarter cd command**, inspired by z and autojump.

It remembers which directories you use most frequently, so you can "jump" to
them in just a few keystrokes.<br />
aiu-shell-jump works on all major shells.

[Getting started](#getting-started) •
[Installation](#installation) •
[Configuration](#configuration) •
[Integrations](#third-party-integrations)

</div>

## Getting started

![Tutorial][tutorial]

```sh
z foo              # cd into highest ranked directory matching foo
z foo bar          # cd into highest ranked directory matching foo and bar
z foo /            # cd into a subdirectory starting with foo

z ~/foo            # z also works like a regular cd command
z foo/             # cd into relative path
z ..               # cd one level up
z -                # cd into previous directory

zi foo             # cd with interactive selection (using fzf)

z foo<SPACE><TAB>  # show interactive completions (bash 4.4+/fish/zsh only)
```

Read more about the matching algorithm [here][algorithm-matching].

## Installation

aiu-shell-jump can be installed in 4 easy steps:

1. **Install binary**

   aiu-shell-jump runs on most major platforms. If your platform isn't listed below,
   please [open an issue][issues].

   <details>
   <summary>Linux / WSL</summary>

   > The recommended way to install aiu-shell-jump is via the install script:
   >
   > ```sh
   > curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
   > ```
   >
   > Or, you can use a package manager:
   >
   > | Distribution        | Repository              | Instructions                                                      |
   > | ------------------- | ----------------------- | ----------------------------------------------------------------- |
   > | **_Any_**           | **[crates.io]**         | `cargo install aiu-shell-jump --locked`                                   |
   > | _Any_               | [conda-forge]           | `conda install -c conda-forge aiu-shell-jump`                             |
   > | _Any_               | [guix]                  | `guix install aiu-shell-jump`                                             |
   > | _Any_               | [Linuxbrew]             | `brew install aiu-shell-jump`                                             |
   > | _Any_               | [nixpkgs]               | `nix-env -iA nixpkgs.aiu-shell-jump`                                      |
   > | Alpine Linux 3.13+  | [Alpine Linux Packages] | `apk add aiu-shell-jump`                                                  |
   > | Arch Linux          | [Arch Linux Extra]      | `pacman -S aiu-shell-jump`                                                |
   > | ~~Debian~~[^1]      | ~~[Debian Packages]~~   | ~~`apt install aiu-shell-jump`~~                                          |
   > | Devuan 4.0+         | [Devuan Packages]       | `apt install aiu-shell-jump`                                              |
   > | Exherbo Linux       | [Exherbo packages]      | `cave resolve -x repository/rust` <br /> `cave resolve -x aiu-shell-jump` |
   > | Fedora 32+          | [Fedora Packages]       | `dnf install aiu-shell-jump`                                              |
   > | Gentoo              | [Gentoo Packages]       | `emerge app-shells/aiu-shell-jump`                                        |
   > | Manjaro             |                         | `pacman -S aiu-shell-jump`                                                |
   > | openSUSE Tumbleweed | [openSUSE Factory]      | `zypper install aiu-shell-jump`                                           |
   > | ~~Parrot OS~~[^1]   |                         | ~~`apt install aiu-shell-jump`~~                                          |
   > | ~~Raspbian~~[^1]    | ~~[Raspbian Packages]~~ | ~~`apt install aiu-shell-jump`~~                                          |
   > | Rhino Linux         | [Pacstall Packages]     | `pacstall -I aiu-shell-jump-deb`                                          |
   > | Slackware 15.0+     | [SlackBuilds]           | [Instructions][slackbuilds-howto]                                 |
   > | Solus               | [Solus Packages]        | `eopkg install aiu-shell-jump`                                            |
   > | ~~Ubuntu~~[^1]      | ~~[Ubuntu Packages]~~   | ~~`apt install aiu-shell-jump`~~                                          |
   > | Void Linux          | [Void Linux Packages]   | `xbps-install -S aiu-shell-jump`                                          |

   </details>

   <details>
   <summary>macOS</summary>

   > To install aiu-shell-jump, use a package manager:
   >
   > | Repository      | Instructions                          |
   > | --------------- | ------------------------------------- |
   > | **[crates.io]** | `cargo install aiu-shell-jump --locked`       |
   > | **[Homebrew]**  | `brew install aiu-shell-jump`                 |
   > | [conda-forge]   | `conda install -c conda-forge aiu-shell-jump` |
   > | [MacPorts]      | `port install aiu-shell-jump`                 |
   > | [nixpkgs]       | `nix-env -iA nixpkgs.aiu-shell-jump`          |
   >
   > Or, run this command in your terminal:
   >
   > ```sh
   > curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
   > ```

   </details>

   <details>
   <summary>Windows</summary>

   > aiu-shell-jump works with PowerShell, as well as shells running in Cygwin, Git
   > Bash, and MSYS2.
   >
   > The recommended way to install aiu-shell-jump is via `winget`:
   >
   > ```sh
   > winget install ajeetdsouza.aiu-shell-jump
   > ```
   >
   > Or, you can use an alternative package manager:
   >
   > | Repository      | Instructions                          |
   > | --------------- | ------------------------------------- |
   > | **[crates.io]** | `cargo install aiu-shell-jump --locked`       |
   > | [Chocolatey]    | `choco install aiu-shell-jump`                |
   > | [conda-forge]   | `conda install -c conda-forge aiu-shell-jump` |
   > | [Scoop]         | `scoop install aiu-shell-jump`                |
   >
   > If you're using Cygwin, Git Bash, or MSYS2, you can also use the install script:
   >
   > ```sh
   > curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
   > ```

   </details>

   <details>
   <summary>BSD</summary>

   > To install aiu-shell-jump, use a package manager:
   >
   > | Distribution  | Repository      | Instructions                    |
   > | ------------- | --------------- | ------------------------------- |
   > | **_Any_**     | **[crates.io]** | `cargo install aiu-shell-jump --locked` |
   > | DragonFly BSD | [DPorts]        | `pkg install aiu-shell-jump`            |
   > | FreeBSD       | [FreshPorts]    | `pkg install aiu-shell-jump`            |
   > | NetBSD        | [pkgsrc]        | `pkgin install aiu-shell-jump`          |
   >
   > Or, run this command in your terminal:
   >
   > ```sh
   > curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
   > ```

   </details>

   <details>
   <summary>Android</summary>

   > To install aiu-shell-jump, use a package manager:
   >
   > | Repository | Instructions         |
   > | ---------- | -------------------- |
   > | [Termux]   | `pkg install aiu-shell-jump` |
   >
   > Or, run this command in your terminal:
   >
   > ```sh
   > curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
   > ```

   </details>

2. **Setup aiu-shell-jump on your shell**

   To start using aiu-shell-jump, add it to your shell.

   <details>
   <summary>Bash</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually `~/.bashrc`):
   >
   > ```sh
   > eval "$(aiu-shell-jump init bash)"
   > ```

   </details>

   <details>
   <summary>Elvish</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually `~/.elvish/rc.elv`):
   >
   > ```sh
   > eval (aiu-shell-jump init elvish | slurp)
   > ```
   >
   > **Note:**
   > aiu-shell-jump only supports elvish v0.18.0 and above.

   </details>

   <details>
   <summary>Fish</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually
   > `~/.config/fish/config.fish`):
   >
   > ```sh
   > aiu-shell-jump init fish | source
   > ```

   </details>

   <details>
   <summary>Nushell</summary>

   > Add this to the <ins>**end**</ins> of your env file (find it by running `$nu.env-path`
   > in Nushell):
   >
   > ```sh
   > aiu-shell-jump init nushell | save -f ~/.aiu-shell-jump.nu
   > ```
   >
   > Now, add this to the <ins>**end**</ins> of your config file (find it by running
   > `$nu.config-path` in Nushell):
   >
   > ```sh
   > source ~/.aiu-shell-jump.nu
   > ```
   >
   > **Note:**
   > aiu-shell-jump only supports Nushell v0.89.0+.

   </details>

   <details>
   <summary>PowerShell</summary>

   > Add this to the <ins>**end**</ins> of your config file (find it by running
   > `echo $profile` in PowerShell):
   >
   > ```powershell
   > Invoke-Expression (& { (aiu-shell-jump init powershell | Out-String) })
   > ```

   </details>

   <details>
   <summary>Tcsh</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually `~/.tcshrc`):
   >
   > ```sh
   > aiu-shell-jump init tcsh > ~/.aiu-shell-jump.tcsh
   > source ~/.aiu-shell-jump.tcsh
   > ```

   </details>

   <details>
   <summary>Xonsh</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually `~/.xonshrc`):
   >
   > ```python
   > execx($(aiu-shell-jump init xonsh), 'exec', __xonsh__.ctx, filename='aiu-shell-jump')
   > ```

   </details>

   <details>
   <summary>Zsh</summary>

   > Add this to the <ins>**end**</ins> of your config file (usually `~/.zshrc`):
   >
   > ```sh
   > eval "$(aiu-shell-jump init zsh)"
   > ```
   >
   > For completions to work, the above line must be added _after_ `compinit` is
   > called. You may have to rebuild your completions cache by running
   > `rm ~/.zcompdump*; compinit`.

   </details>

   <details>
   <summary>Any POSIX shell</summary>

   > Add this to the <ins>**end**</ins> of your config file:
   >
   > ```sh
   > eval "$(aiu-shell-jump init posix --hook prompt)"
   > ```

   </details>

   > **Note:**
   > [Warp] provides its own completions, so `Space+Tab` completions are not
   > supported there.

3. **Install fzf** <sup>(optional)</sup>

   [fzf] is a command-line fuzzy finder, used by aiu-shell-jump for completions /
   interactive selection. It can be installed from [here][fzf-installation].

   > **Note:**
   > The minimum supported fzf version is v0.51.0.

4. **Import your data** <sup>(optional)</sup>

   If you currently use any of these plugins, you may want to import your data
   into aiu-shell-jump. The data file is auto-detected using each plugin's standard
   conventions.

   ```sh
   aiu-shell-jump import <plugin>
   ```

   | Plugin   | Command                  |
   | -------- | ------------------------ |
   | atuin    | `aiu-shell-jump import atuin`    |
   | autojump | `aiu-shell-jump import autojump` |
   | fasd     | `aiu-shell-jump import fasd`     |
   | z        | `aiu-shell-jump import z`        |
   | z.lua    | `aiu-shell-jump import z.lua`    |
   | zsh-z    | `aiu-shell-jump import zsh-z`    |

## Configuration

### Flags

When calling `aiu-shell-jump init`, the following flags are available:

- `--cmd`
  - Changes the prefix of the `z` and `zi` commands.
  - `--cmd j` would change the commands to (`j`, `ji`).
  - `--cmd cd` would replace the `cd` command.
- `--hook <HOOK>`
  - Changes how often aiu-shell-jump increments a directory's score:

    | Hook            | Description                       |
    | --------------- | --------------------------------- |
    | `none`          | Never                             |
    | `prompt`        | At every shell prompt             |
    | `pwd` (default) | Whenever the directory is changed |

- `--no-cmd`
  - Prevents aiu-shell-jump from defining the `z` and `zi` commands.
  - These functions will still be available in your shell as `__aiu_shell_jump_z` and
    `__aiu_shell_jump_zi`, should you choose to redefine them.

### Environment variables

Environment variables[^2] can be used for configuration. They must be set before
`aiu-shell-jump init` is called.

- `_ZO_DATA_DIR`
  - Specifies the directory in which the database is stored.
  - The default value varies across OSes:

    | OS          | Path                                     | Example                                    |
    | ----------- | ---------------------------------------- | ------------------------------------------ |
    | Linux / BSD | `$XDG_DATA_HOME` or `$HOME/.local/share` | `/home/alice/.local/share`                 |
    | macOS       | `$HOME/Library/Application Support`      | `/Users/Alice/Library/Application Support` |
    | Windows     | `%LOCALAPPDATA%`                         | `C:\Users\Alice\AppData\Local`             |

- `_ZO_ECHO`
  - When set to 1, `z` will print the matched directory before navigating to
    it.
- `_ZO_EXCLUDE_DIRS`
  - Excludes the specified directories from the database.
  - This is provided as a list of [globs][glob], separated by OS-specific
    characters:

    | OS                  | Separator | Example                 |
    | ------------------- | --------- | ----------------------- |
    | Linux / macOS / BSD | `:`       | `$HOME:$HOME/private/*` |
    | Windows             | `;`       | `$HOME;$HOME/private/*` |

  - By default, this is set to `"$HOME"`.
- `_ZO_FZF_OPTS`
  - Custom options to pass to [fzf] during interactive selection. See
    [`man fzf`][fzf-man] for the list of options.
- `_ZO_MAXAGE`
  - Configures the [aging algorithm][algorithm-aging], which limits the maximum
    number of entries in the database.
  - By default, this is set to 10000.
- `_ZO_RESOLVE_SYMLINKS`
  - When set to 1, `z` will resolve symlinks before adding directories to the
    database.

## Third-party integrations

| Application           | Description                                  | Plugin                     |
| --------------------- | -------------------------------------------- | -------------------------- |
| [aerc]                | Email client                                 | Natively supported         |
| [alfred]              | macOS launcher                               | [alfred-aiu-shell-jump]            |
| [clink]               | Improved cmd.exe for Windows                 | [clink-aiu-shell-jump]             |
| [emacs]               | Text editor                                  | [aiu-shell-jump.el]                |
| [felix]               | File manager                                 | Natively supported         |
| [joshuto]             | File manager                                 | Natively supported         |
| [lf]                  | File manager                                 | See the [wiki][lf-wiki]    |
| [nnn]                 | File manager                                 | [nnn-autojump]             |
| [ranger]              | File manager                                 | [ranger-aiu-shell-jump]            |
| [raycast]             | macOS launcher                               | [raycast-aiu-shell-jump]           |
| [rfm]                 | File manager                                 | Natively supported         |
| [sesh]                | `tmux` session manager                       | Natively supported         |
| [telescope.nvim]      | Fuzzy finder for Neovim                      | [telescope-aiu-shell-jump]         |
| [tmux-session-wizard] | `tmux` session manager                       | Natively supported         |
| [tmux-sessionx]       | `tmux` session manager                       | Natively supported         |
| [vim] / [neovim]      | Text editor                                  | [aiu-shell-jump.vim]               |
| [xplr]                | File manager                                 | [aiu-shell-jump.xplr]              |
| [xxh]                 | Transports shell configuration over SSH      | [xxh-plugin-prerun-aiu-shell-jump] |
| [yazi]                | File manager                                 | Natively supported         |
| [zabb]                | Finds the shortest possible query for a path | Natively supported         |
| [zesh]                | `zellij` session manager                     | Natively supported         |
| [zsh-autocomplete]    | Realtime completions for zsh                 | Natively supported         |

[^1]:
    Debian / Ubuntu derivatives update their packages very slowly. If you're
    using one of these distributions, consider using the install script instead.

[^2]:
    If you're not sure how to set an environment variable on your shell, check
    out the [wiki][wiki-env].

[aerc]: https://github.com/rjarry/aerc
[alfred]: https://www.alfredapp.com/
[alfred-aiu-shell-jump]: https://github.com/yihou/alfred-zoxide
[algorithm-aging]: https://github.com/ajeetdsouza/zoxide/wiki/Algorithm#aging
[algorithm-matching]: https://github.com/ajeetdsouza/zoxide/wiki/Algorithm#matching
[alpine linux packages]: https://pkgs.alpinelinux.org/packages?name=zoxide
[arch linux extra]: https://archlinux.org/packages/extra/x86_64/zoxide/
[builtwithnix-badge]: https://img.shields.io/badge/builtwith-nix-7d81f7?logo=nixos&logoColor=white&style=flat-square
[builtwithnix]: https://builtwithnix.org/
[chocolatey]: https://community.chocolatey.org/packages/zoxide
[clink-aiu-shell-jump]: https://github.com/shunsambongi/clink-zoxide
[clink]: https://github.com/mridgers/clink
[conda-forge]: https://anaconda.org/conda-forge/zoxide
[crates.io-badge]: https://img.shields.io/crates/v/zoxide?logo=rust&logoColor=white&style=flat-square
[crates.io]: https://crates.io/crates/zoxide
[debian packages]: https://packages.debian.org/stable/admin/zoxide
[exherbo packages]: https://gitlab.exherbo.org/exherbo/rust/-/tree/master/packages/sys-apps/zoxide
[devuan packages]: https://pkginfo.devuan.org/cgi-bin/package-query.html?c=package&q=zoxide
[downloads-badge]: https://img.shields.io/github/downloads/ajeetdsouza/zoxide/total?logo=github&logoColor=white&style=flat-square
[dports]: https://github.com/DragonFlyBSD/DPorts/tree/master/sysutils/zoxide
[emacs]: https://www.gnu.org/software/emacs/
[fedora packages]: https://src.fedoraproject.org/rpms/rust-zoxide
[felix]: https://github.com/kyoheiu/felix
[freshports]: https://www.freshports.org/sysutils/zoxide/
[fzf-installation]: https://github.com/junegunn/fzf#installation
[fzf-man]: https://manpages.ubuntu.com/manpages/en/man1/fzf.1.html
[fzf]: https://github.com/junegunn/fzf
[gentoo packages]: https://packages.gentoo.org/packages/app-shells/zoxide
[glob]: https://man7.org/linux/man-pages/man7/glob.7.html
[guix]: https://packages.guix.gnu.org/packages/zoxide/
[homebrew]: https://formulae.brew.sh/formula/zoxide
[issues]: https://github.com/ajeetdsouza/zoxide/issues/new
[joshuto]: https://github.com/kamiyaa/joshuto
[lf]: https://github.com/gokcehan/lf
[lf-wiki]: https://github.com/gokcehan/lf/wiki/Integrations#zoxide
[linuxbrew]: https://formulae.brew.sh/formula-linux/zoxide
[macports]: https://ports.macports.org/port/zoxide/summary
[neovim]: https://github.com/neovim/neovim
[nixpkgs]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/zo/zoxide/package.nix
[nnn-autojump]: https://github.com/jarun/nnn/blob/master/plugins/autojump
[nnn]: https://github.com/jarun/nnn
[opensuse factory]: https://build.opensuse.org/package/show/openSUSE:Factory/zoxide
[pacstall packages]: https://pacstall.dev/packages/zoxide-deb
[pkgsrc]: https://pkgsrc.se/sysutils/zoxide
[ranger-aiu-shell-jump]: https://github.com/jchook/ranger-zoxide
[ranger]: https://github.com/ranger/ranger
[raspbian packages]: https://archive.raspbian.org/raspbian/pool/main/r/rust-zoxide/
[raycast]: https://www.raycast.com/
[raycast-aiu-shell-jump]: https://www.raycast.com/mrpunkin/raycast-zoxide
[releases]: https://github.com/ajeetdsouza/zoxide/releases
[rfm]: https://github.com/dsxmachina/rfm
[scoop]: https://github.com/ScoopInstaller/Main/tree/master/bucket/zoxide.json
[sesh]: https://github.com/joshmedeski/sesh
[slackbuilds]: https://slackbuilds.org/repository/15.0/system/zoxide/
[slackbuilds-howto]: https://slackbuilds.org/howto/
[solus packages]: https://github.com/getsolus/packages/tree/main/packages/z/zoxide/
[telescope-aiu-shell-jump]: https://github.com/jvgrootveld/telescope-zoxide
[telescope.nvim]: https://github.com/nvim-telescope/telescope.nvim
[termux]: https://github.com/termux/termux-packages/tree/master/packages/zoxide
[tmux-session-wizard]: https://github.com/27medkamal/tmux-session-wizard
[tmux-sessionx]: https://github.com/omerxx/tmux-sessionx
[tutorial]: contrib/tutorial.webp
[ubuntu packages]: https://packages.ubuntu.com/jammy/zoxide
[vim]: https://github.com/vim/vim
[void linux packages]: https://github.com/void-linux/void-packages/tree/master/srcpkgs/zoxide
[warp]: https://www.warp.dev
[wiki-env]: https://github.com/ajeetdsouza/zoxide/wiki/HOWTO:-set-environment-variables "HOWTO: set environment variables"
[xplr]: https://github.com/sayanarijit/xplr
[xxh-plugin-prerun-aiu-shell-jump]: https://github.com/xxh/xxh-plugin-prerun-zoxide
[xxh]: https://github.com/xxh/xxh
[yazi]: https://github.com/sxyazi/yazi
[zabb]: https://github.com/Mellbourn/zabb
[zesh]: https://github.com/roberte777/zesh
[aiu-shell-jump.el]: https://gitlab.com/Vonfry/zoxide.el
[aiu-shell-jump.vim]: https://github.com/nanotee/zoxide.vim
[aiu-shell-jump.xplr]: https://github.com/sayanarijit/zoxide.xplr
[zsh-autocomplete]: https://github.com/marlonrichert/zsh-autocomplete
