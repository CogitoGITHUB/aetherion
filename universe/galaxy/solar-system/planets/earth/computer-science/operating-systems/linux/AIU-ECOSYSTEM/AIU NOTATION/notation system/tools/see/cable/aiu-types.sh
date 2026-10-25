#!/usr/bin/env bash
# aiu-types.sh: prints the file type names, one per line, then the entry new-type, for the tv list.
# Called by: cable/aiu-types.toml. Reads the starter pages in the types folder.
d=$(cd "$(dirname "$0")" && pwd)
for f in "$d"/../../../../types/*.aiu; do b=${f##*/}; echo "${b%.aiu}"; done
echo "new-type"
