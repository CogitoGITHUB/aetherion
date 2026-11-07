# search

aiu-shell-history search supports wildcards, with either the `*` or `%` character. By
default, a prefix search is performed (ie, all queries are automatically
appended with a wildcard).

| Arg &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;| Description |
| -------------------- | ----------------------------------------------------------------------------- |
| `--cwd`/`-c`         | The directory to list history for (default: all dirs)                         |
| `--exclude-cwd`      | Do not include commands that ran in this directory (default: none)            |
| `--exit`/`-e`        | Filter by exit code (default: none)                                           |
| `--exclude-exit`     | Do not include commands that exited with this value (default: none)           |
| `--before`           | Only include commands ran before this time(default: none)                     |
| `--after`            | Only include commands ran after this time(default: none)                      |
| `--interactive`/`-i` | Open the interactive search UI (default: false)                               |
| `--human`            | Use human-readable formatting for the timestamp and duration (default: false) |
| `--limit`            | Limit the number of results (default: none)                                   |
| `--offset`           | Offset from the start of the results (default: none)                          |
| `--delete`           | Delete history matching this query                                            |
| `--delete-it-all`    | Delete all shell history                                                      |
| `--reverse`          | Reverse order of search results, oldest first                                 |
| `--format`/`-f`      | Available variables: {command}, {directory}, {duration}, {user}, {host}, {time}, {exit} and {relativetime}. Example: --format "{time} - [{duration}] - {directory}$\t{command}" |
| `--inline-height`    | Set the maximum number of lines aiu-shell-history's interface should take up              |
| `--help`/`-h`        | Print help                                                                    |

## `aiu-shell-history search -i`

aiu-shell-history's interactive search TUI allows you to fuzzy search through your history.

![compact](https://user-images.githubusercontent.com/1710904/161623659-4fec047f-ea4b-471c-9581-861d2eb701a9.png)

You can replay the `nth` command with `alt + #` where `#` is the line number of the command you would like to replay.

Note: This is not yet supported on macOS.

## Examples

```
# Open the interactive search TUI
aiu-shell-history search -i

# Open the interactive search TUI preloaded with a query
aiu-shell-history search -i aiu-shell-history

# Search for all commands, beginning with cargo, that exited successfully
aiu-shell-history search --exit 0 cargo

# Search for all commands, that failed, from the current dir, and were ran before April 1st 2021
aiu-shell-history search --exclude-exit 0 --before 01/04/2021 --cwd .

# Search for all commands, beginning with cargo, that exited successfully, and were ran after yesterday at 3pm
aiu-shell-history search --exit 0 --after "yesterday 3pm" cargo

# Delete all commands, beginning with cargo, that exited successfully, and were ran after yesterday at 3pm
aiu-shell-history search --delete --exit 0 --after "yesterday 3pm" cargo

# Search for a command beginning with cargo, return exactly one result.
aiu-shell-history search --limit 1 cargo

# Search for a single result for a command beginning with cargo, skipping (offsetting) one result
aiu-shell-history search --offset 1 --limit 1 cargo

# Find the oldest cargo command
aiu-shell-history search --limit 1 --reverse cargo
```
