# Plugin Example

Crate with a simple example of the Plugin trait that needs to be implemented
in order to create a binary that can be registered into aiu-shell declaration list

## `example config`

This subcommand demonstrates sending configuration from the aiu-shell `$env.config` to a plugin.

To make use of the plugin after building `aiu-shell` run:

```aiu-shell
plugin add target/debug/aiu_shell_plugin_example
# or then either restart your current aiu-shell session or run:
plugin use target/debug/aiu_shell_plugin_example
```

The configuration for the plugin lives in `$env.config.plugins.example`:

```aiu-shell
$env.config = {
  plugins: {
    example: [
      some
      values
    ]
  }
}
```

To list plugin values run:

```aiu-shell
example config
```

