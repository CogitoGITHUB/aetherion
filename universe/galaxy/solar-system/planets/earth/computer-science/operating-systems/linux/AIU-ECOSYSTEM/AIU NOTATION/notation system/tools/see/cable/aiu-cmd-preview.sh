#!/usr/bin/env bash
# aiu-cmd-preview.sh: prints usage and description of one aiu command for the tv preview pane.
# Called by: cable/aiu-commands.toml. Argument: the selected line of aiu-commands.txt.
d=$(cd "$(dirname "$0")" && pwd)
w=$(bash "$d/../fitwidth.sh")
IFS=";" read -r name usage desc <<< "$1"
printf "%s\n\nUsage:\n  %s\n\n%s\n" "$name" "$usage" "$desc" | fold -s -w "$w"
