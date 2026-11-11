#!/bin/sh
SELF=$(cd "$(dirname "$0")" && pwd)
DIR=$(dirname "$SELF")
PREFIX=$(dirname "$(dirname "$DIR")")
CLI="$DIR/text-editor/editor/entry/cli.rkt"
RACKET="${AIU_RACKET_BIN:-$HOME/opt/racket-full/bin/racket}"
NOTATION="$PREFIX/aiu-notation/current/bin/notation"
if [ -z "$AIU_NOTATION_BIN" ] && [ -x "$NOTATION" ]; then AIU_NOTATION_BIN="$NOTATION"; export AIU_NOTATION_BIN; fi
if [ -z "$AIU_HOT_PATH_BIN" ]; then AIU_HOT_PATH_BIN="$DIR/bin/hot-path"; export AIU_HOT_PATH_BIN; fi
export PLTCOMPILEDROOTS="$HOME/aiu-compiled" AIU_ROOT="$DIR" LANG=C.UTF-8 LC_ALL=C.UTF-8
case "$1" in
update|test|docs|trace|record|record-module) exec "$RACKET" "$CLI" "$@" ;;
esac
if [ -z "$1" ]; then exec "$RACKET" "$CLI" edit; fi
exec "$RACKET" "$CLI" edit "$1"
