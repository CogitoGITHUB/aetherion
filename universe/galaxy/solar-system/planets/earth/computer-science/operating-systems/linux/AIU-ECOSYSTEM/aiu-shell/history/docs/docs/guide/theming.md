# Theming

Available in aiu-shell-history >= 18.4

For terminal interface customization, aiu-shell-history supports user and built-in color themes.

aiu-shell-history ships with only a couple of built-in alternative themes, but more can be added via TOML files.

## Required config

The following is required in your config file (`~/.config/aiu-shell-history/config.toml`)

```
[theme]
name = "THEMENAME"
```

Where `THEMENAME` is a known theme. The following themes are available out-of-the-box:

* `default` theme
* `autumn` theme
* `marine` theme
* `(none)` theme (removes all styling)

These are present to ensure users and developers can try out theming, but in general, you
will need to download themes or make your own.

If you are writing your own themes, you can add the following line to get additional output:

```
debug = true
```

to the same config block. This will print out any color names that cannot be parsed from
the requested theme.

A final optional setting is available:

```
max_depth: 10
```

which sets the maximum levels of theme parents to traverse. This should not need to be
explicitly added in normal use.

## Usage

### Theme structure

Themes are maps from *Meanings*, describing the developer's intentions,
to (at present) colors. In future, this may be expanded to allow richer style support.

*Meanings* are from an enum with the following values:

* `AlertInfo`: alerting the user at an INFO level
* `AlertWarn`: alerting the user at a WARN level
* `AlertError`: alerting the user at an ERROR level
* `Annotation`: less-critical, supporting text
* `Base`: default foreground color
* `Guidance`: instructing the user as help or context
* `Important`: drawing the user's attention to information
* `Title`: titling a section or view
* `Muted`: anodyne, usually grey, foreground for contrast with other colors. Normally equivalent to the base color, but allows themes to change the base color, with less risk of breaking intentional color contrasts (e.g. stacked bar charts)

These may expand over time as they are added to aiu-shell-history's codebase, but aiu-shell-history
should have fallbacks added for any new *Meanings* so that, whether themes limit to
the present list or take advantage of new *Meanings* in future, they should
keep working sensibly.

**Note for aiu-shell-history contributors**: please do identify and, where appropriate during your own
PRs, extend the Meanings enum if needed (along with a fallback Meaning!).

### Theme creation

When a theme name is read but not yet loaded, aiu-shell-history will look for it in the folder
`~/.config/aiu-shell-history/themes/` unless overridden by the `AIU_SHELL_HISTORY_THEME_DIR` environment
variable. It will attempt to open a file of name `THEMENAME.toml` and read it as a
map from *Meanings* to foreground colors.

Note that, at present, it is not possible to specify the default terminal color explicitly
in a theme file. However, the default theme Base color will always be unset and therefore
will be the user's default terminal color. Hence, you should only override the Base color
in your theme, or derive from a theme that does so, if your theme would not make sense
otherwise (e.g. the `marine` theme is intended to make everything green/blue, so it does,
but the `autumn` theme only seeks to make the custom colors warmer, so it does not).

Colors may be specified either as names from the [palette](https://ogeon.github.io/docs/palette/master/palette/named/index.html)
crate in lowercase, or as six-character hex codes, prefixed with `#`. To explicitly select ANSI colors by integer, or for greater flexibility in general, you can prefix with `@` and the rest of the string will be handled by crossterm's color parsing. For examples, see [crossterm's color deserialization tests](https://github.com/crossterm-rs/crossterm/blob/5d50d8da62c5e034ef8b2787a771a2c0f9b3b2f9/src/style/types/color.rs#L389), remembering the need to add a `@` prefix for aiu-shell-history.

For example, the following are valid color names:

* `#ff0088`
* `teal`
* `powderblue`
* `@ansi_(255)`
* `@rgb_(255, 128, 0)`

You can also express colors through Crossterm-supported strings, prefixed by `@`.
For example,

* `@ansi_(123)`
* `@dark_yellow`

While there is not currently an official reference, you can see examples in the
[crossterm tests](https://docs.rs/crossterm/latest/src/crossterm/style/types/color.rs.html#376).
As this is passed straight to Crossterm, using [ANSI codes](https://www.ditig.com/256-colors-cheat-sheet)
can be helpful for ensuring your theme is compatible with 256-color terminals.

A theme file, say `my-theme.toml` can then be built up, such as:

```toml
[theme]
name = "my-theme"
parent = "autumn"

[colors]
AlertInfo = "green"
Guidance = "#888844"

```

where not all of the *Meanings* need to be explicitly defined. If they are absent,
then the color will be chosen from the parent theme, if one is defined, or if that
key is missing in the `theme` block, from the `default` theme.

If the entire named theme is missing, which is inherently an error, then the theme
will drop to `(none)` and leave aiu-shell-history unstyled, rather than trying to fallback to
the any default, or other, theme.

This theme file should be moved to `~/.config/aiu-shell-history/themes/my-theme.toml` and the
following added to `~/.config/aiu-shell-history/config.toml`:

```
[theme]
name = "my-theme"
```

When you next run aiu-shell-history, your theme should be applied.
