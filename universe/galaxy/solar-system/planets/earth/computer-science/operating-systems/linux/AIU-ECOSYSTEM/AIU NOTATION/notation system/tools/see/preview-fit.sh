#!/usr/bin/env bash
# preview-fit.sh: runs preview.sh with a width that fits the tv preview pane.
# Called by: cable/aiu-pages.toml and cable/aiu-type-preview.sh. Argument: the page file.
d=$(cd "$(dirname "$0")" && pwd)
w=$(bash "$d/fitwidth.sh")
case "$2" in --*) x="$2";; *) x="";; esac
exec bash "$d/preview.sh" "$1" "$w" "$x"
