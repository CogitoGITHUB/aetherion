#!/usr/bin/env bash
# newblock-guide.sh: checks a new block name and prints the places a new block touches, read from the code.
# Called by: the new-block entry of the aiu list menu and cable/aiu-list-preview.sh. Argument: the name, or --preview. Edits nothing.
d=$(cd "$(dirname "$0")" && pwd)
ns=$(cd "$d/../.." && pwd)
w=$(bash "$d/fitwidth.sh")
p="$ns/notation/src/parser/parser.rs"
r="$ns/notation/src/elements/register.rkt"
l="$ns/gate/register-lint.nu"
n=$1
mode=name
if [ "$n" = "--preview" ]; then
  n="NAME"; mode=preview
else
  case $n in ""|[!a-z]*|*[!a-z-]*) echo "A block name is lowercase letters and dashes: $n"; exit 1 ;; esac
  if bash "$d/cable/aiu-list.sh" blocks-only | grep -qx -- "$n"; then echo "The parser already has a block named $n."; exit 1; fi
fi
ln=$(grep -n "BLOCK_NAMES" "$p" | head -1 | cut -d: -f1)
c=$(sed -n "${ln}p" "$p" | grep -o "[0-9][0-9]*" | head -1)
{
  echo "NEW BLOCK $n"
  echo
  if [ "$mode" = preview ]; then
    echo "Enter asks for a name, checks it, and prints this list for that name. Nothing is edited for you."
    echo
  fi
  echo "== 1. parser.rs, line $ln"
  sed -n "${ln},$((ln+8))p" "$p"
  echo "Set the count to $((c+1)) and add \"$n\", to the list."
  echo
  echo "== 2. register.rkt, the block table"
  grep -n -E "\"(section|title|paragraph|code|heading|comment)\"" "$r" | head -8
  echo "Add \"$n\" the same way as the entries above."
  echo
  echo "== 3. exceptions (gate/register-lint.nu), only if the checker should not know it"
  grep -n -E "table|header|row" "$l" | head -4
  echo
  echo "== 4. allow it in a file type (filetypes/types/NAME.rkt), then run: aiu update, aiu gate"
} | fold -s -w "$w"
