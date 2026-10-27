#!/usr/bin/env bash
# aiu-list-preview-fit.sh: details for the aiu list menus, read from the code.
# Called by: cable/aiu-list-kind.toml, aiu-list-blocks.toml, aiu-list-types.toml. Arguments: kind (kind, block or type), entry.
d=$(cd "$(dirname "$0")" && pwd)
ns=$(cd "$d/../../.." && pwd)
export AIU_NOTATION_ROOT=$ns
w=$(bash "$d/../preview-fit.sh" --width)
src="$ns/notation/src"
t="$src/filetypes/types"
kind=$1
name=${2%%;*}
case $kind in
kind)
  {
    if [ "$name" = "blocks" ]; then
      echo "BLOCKS"; echo "The block names the parser knows (parser.rs)."; echo
      bash "$d/aiu-list.sh" blocks-only
    else
      echo "FILE TYPES"; echo "The types that load, one module each."; echo
      grep -rh "file-type \"" "$t"/*.rkt "$t"/*/type.rkt 2>/dev/null | sed -E "s/.*file-type \"([^\"]*)\" \"([^\"]*)\".*/\1: \2/"
    fi
  } | fold -s -w "$w" ;;
block)
  if [ "$name" = "new-block" ]; then bash "$d/../newblock-guide.sh" --preview; exit 0; fi
  {
    echo "BLOCK $name"
    echo
    echo "== FILE TYPES THAT ALLOW IT"
    for e in "$t"/*; do
      n=${e##*/}; case $n in _*) continue ;; esac; n=${n%.rkt}
      if grep -rqE "file-type \"$n\" \"[^\"]*\" #f\)" "$e" 2>/dev/null; then echo "$n: any block"
      elif grep -rqF -- "\"$name\"" "$e" 2>/dev/null; then echo "$n: yes"; fi
    done
    echo
    echo "== NAMED IN THE PARSER (parser.rs)"
    grep -n -F -- "\"$name\"" "$src/parser/parser.rs" | head -6
    echo
    echo "== NAMED BY THE CHECKER (register.rkt)"
    r=$(grep -n -F -- "\"$name\"" "$src/elements/register.rkt" | head -6)
    if [ -n "$r" ]; then echo "$r"; else echo "(not registered: parsed only)"; fi
  } | fold -s -w "$w" ;;
*)
  if [ "$name" = "new-type" ]; then bash "$d/aiu-type-preview-fit.sh" new-type; exit 0; fi
  e="$t/$name.rkt"; [ -e "$e" ] || e="$t/$name"
  {
    echo "TYPE $name"
    echo
    echo "== DEFINITION"
    grep -rh -- "file-type \"$name\"" "$e"
    grep -rh -A4 -E "^\(define [a-z-]*blocks" "$e"
    echo
    echo "== MODULE"
    echo "${e#"$ns"/}"
  } | fold -s -w "$w"
  echo
  echo "== STARTER PAGE"
  bash "$d/../preview-fit.sh" "$ns/../types/$name.aiu" ;;
esac
