#!/usr/bin/env bash
# aiu-list.sh: prints the entries of one aiu list, one name per line.
# Called by: cable/aiu-list-blocks.toml, cable/aiu-list-types.toml and aiu-list-preview.sh.
# Argument: blocks, types, blocks-only or types-only; the first two add the entry new-block or new-type.
d=$(cd "$(dirname "$0")" && pwd)
ns=$(cd "$d/../../.." && pwd)
t="$ns/notation/src/filetypes/types"
# Prints the block names of BLOCK_NAMES in parser.rs.
names_blocks() {
  awk "/BLOCK_NAMES/{p=1;next} p&&/];/{exit} p" "$ns/notation/src/parser/parser.rs" | grep -o "\"[a-z-]*\"" | tr -d "\""
}
# Prints the names of the type modules (a file or a folder with type.rkt).
names_types() {
  for f in "$t"/*; do
    b=${f##*/}
    case $b in _*) continue ;; esac
    if [ -d "$f" ]; then
      [ -e "$f/type.rkt" ] && echo "$b"
    else
      case $b in *.rkt) echo "${b%.rkt}" ;; esac
    fi
  done
}
case $1 in
blocks) names_blocks; echo "new-block" ;;
blocks-only) names_blocks ;;
types) names_types; echo "new-type" ;;
types-only) names_types ;;
esac
