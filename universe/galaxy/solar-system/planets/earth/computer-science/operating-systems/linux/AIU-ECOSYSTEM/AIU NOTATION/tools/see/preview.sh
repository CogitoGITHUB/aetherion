#!/usr/bin/env bash
# preview.sh -- print one .aiu page, formatted, for a fuzzy finder's preview pane.
# Why: starting Racket takes about a second on the phone, so the formatted page is
# cached in /tmp and reused until the file or the width changes.
# Called by: pick.sh (the preview pane).
# Usage: preview.sh FILE [WIDTH]
f="$1"
w="${2:-60}"
if [ ! -f "$f" ]; then
  echo "no such file: $f"
  exit 0
fi
here="$(cd "$(dirname "$0")" && pwd)"
dir=/tmp/aiu-preview
mkdir -p "$dir"
key=$(printf '%s|%s|%s' "$(readlink -f "$f")" "$(stat -c %Y "$f")" "$w" | md5sum | cut -c1-20)
out="$dir/$key"
if [ ! -s "$out" ]; then
  LC_ALL=C.UTF-8 "${AIU_RACKET:-racket}" "$here/see.rkt" "$f" --width "$w" > "$out.$$" 2>&1
  mv "$out.$$" "$out"
fi
cat "$out"
exit 0
