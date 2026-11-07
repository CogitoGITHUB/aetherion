# Syncing dotfiles

While aiu-shell-history started as a tool for syncing and searching shell history, we are
building tooling for syncing dotfiles across machines, and making them easier
to work with.

At the moment, we support managing and syncing of shell aliases and environment variables - with more
coming soon.

The following shells are supported:

- zsh
- bash
- fish
- xonsh
- powershell

Note: aiu-shell-history handles your configuration internally, so once it is installed you
no longer need to edit your config files manually.

## Required config

Once aiu-shell-history is set up and installed, the following is required in your config file (`~/.config/aiu-shell-history/config.toml`)

```
[dotfiles]
enabled = true
```

In a later release, this will be enabled by default.

Note: If you have not yet set up sync v2, please also add

```
[sync]
records = true
```

to the same config file.

## Usage

### Aliases

After creating or deleting an alias, remember to restart your shell!

#### Creating an alias

```
aiu-shell-history dotfiles alias set NAME 'COMMAND'
```

For example, to alias `k` to be `kubectl`


```
aiu-shell-history dotfiles alias set k 'kubectl'
```

or to alias `ll` to be  `ls -lah`

```
aiu-shell-history dotfiles alias set ll 'ls -lah'
```

#### Deleting an alias

Deleting an alias is as simple as:

```
aiu-shell-history dotfiles alias delete NAME
```

For example, to delete the above alias `k`:

```
aiu-shell-history dotfiles alias delete k
```

#### Listing aliases

You can list all aliases with:

```
aiu-shell-history dotfiles alias list
```

### Env vars

After creating or deleting an env var, remember to restart your shell!

#### Creating a var

```
aiu-shell-history dotfiles var set NAME 'value'
```

For example, to set `FOO` to be `bar`


```
aiu-shell-history dotfiles var set FOO 'bar'
```

Vars are exported by default, but you can create a shell var like so

```
aiu-shell-history dotfiles var set -n foo 'bar'
```


#### Deleting a var

Deleting a var is as simple as:

```
aiu-shell-history dotfiles var delete NAME
```

For example, to delete the above var `FOO`:

```
aiu-shell-history dotfiles var delete FOO
```

#### Listing vars

You can list all vars with:

```
aiu-shell-history dotfiles var list
```

### Syncing and backing up dotfiles
If you have [set up sync](sync.md), then running

```
aiu-shell-history sync
```

will back up your config to the server and sync it across machines.
