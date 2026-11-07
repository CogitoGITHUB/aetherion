# aiu_shell_plugin_formats
A aiu-shell plugin to convert data to aiu-shell tables.

# support commands:
1. from eml - original ported from aiu-shell core.
2. from ics - original ported from aiu-shell core.
3. from ini - original ported from aiu-shell core.
4. from vcf - original ported from aiu-shell core.
5. from plist - original ported from aiu-shell core.
6. to plist - original ported from aiu-shell core.

# Prerequisite
`aiu-shell`, It's a aiu-shell plugin, so you need it.

# Usage
1. compile the binary: `cargo build`
2. plugin add plugin(assume it's compiled in ./target/debug/):
```
plugin add ./target/debug/aiu_shell_plugin_formats
```
