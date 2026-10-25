#!/usr/bin/env bash
# fitwidth.sh: prints a text width that fits the tv preview pane (terminal width minus 6).
# Called by: preview-fit.sh and the preview scripts in cable/.
c=$(stty size </dev/tty 2>/dev/null | cut -d" " -f2)
case $c in ""|*[!0-9]*) c=56 ;; esac
w=$((c - 6))
[ "$w" -lt 30 ] && w=30
echo "$w"
