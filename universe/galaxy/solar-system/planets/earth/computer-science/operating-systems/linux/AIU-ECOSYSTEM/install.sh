#!/usr/bin/env bash
set -eu
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "$0")" && pwd)"
OPT="${AIU_OPT:-$HOME/opt}"
WORK="${AIU_WORK:-$HOME/aiu-install-work}"
RACKET_VERSION="${AIU_RACKET_VERSION:-9.3}"
RUST_VERSION="${AIU_RUST_VERSION:-1.99.0}"
JOBS="${AIU_JOBS:-2}"
DRY="${AIU_INSTALL_DRY:-}"
RACKET_DIR="$OPT/racket-full"
CARGO_DIR="$HOME/.cargo"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

say() { printf "== %s\n" "$*"; }
die() { printf "FAILED: %s\n" "$*" >&2; exit 1; }
run() { if [ -n "$DRY" ]; then printf "would run: %s\n" "$*"; else "$@"; fi; }
inside() { d="$1"; shift; if [ -n "$DRY" ]; then printf "would run in %s: %s\n" "$d" "$*"; else ( cd "$d" && "$@" ); fi; }
fetch() {
  if [ -n "$DRY" ]; then printf "would download: %s\n" "$1"; return 0; fi
  if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -O "$2" "$1"
  else die "need curl or wget"; fi
}

[ "$(uname -o 2>/dev/null || true)" = "Android" ] && die "Android libc is not supported: use a proot distro or a Linux distro"
case "$(uname -m)" in
  aarch64|arm64) RUST_ARCH=aarch64 ;;
  x86_64|amd64) RUST_ARCH=x86_64 ;;
  *) die "unsupported machine type $(uname -m)" ;;
esac

say "checking tools"
missing=""
for t in cc make tar xz gzip; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || missing="$missing curl-or-wget"
[ -z "$missing" ] || die "missing tools:$missing (install them from source or with your system, then run again)"
for h in openssl/ssl.h zlib.h sqlite3.h; do
  found=0
  for d in /usr/include /usr/local/include /usr/include/*-linux-gnu; do [ -f "$d/$h" ] && found=1; done
  [ "$found" = 1 ] || say "warning: header $h not found, some Rust crates may fail to build"
done

run mkdir -p "$WORK"

if [ -x "$RACKET_DIR/bin/racket" ]; then
  say "racket present at $RACKET_DIR"
else
  say "racket: building $RACKET_VERSION from source (long)"
  fetch "https://download.racket-lang.org/installers/$RACKET_VERSION/racket-$RACKET_VERSION-src.tgz" "$WORK/racket-src.tgz"
  run tar -xzf "$WORK/racket-src.tgz" -C "$WORK"
  run mkdir -p "$WORK/racket-$RACKET_VERSION/src/build"
  inside "$WORK/racket-$RACKET_VERSION/src/build" ../configure --prefix="$RACKET_DIR"
  inside "$WORK/racket-$RACKET_VERSION/src/build" make -j "$JOBS"
  inside "$WORK/racket-$RACKET_VERSION/src/build" make install
fi

if [ -x "$CARGO_DIR/bin/cargo" ] || command -v cargo >/dev/null 2>&1; then
  say "cargo present"
else
  say "rust: installing $RUST_VERSION from the official tarball"
  NAME="rust-$RUST_VERSION-$RUST_ARCH-unknown-linux-gnu"
  fetch "https://static.rust-lang.org/dist/$NAME.tar.xz" "$WORK/rust.tar.xz"
  run tar -xJf "$WORK/rust.tar.xz" -C "$WORK"
  inside "$WORK/$NAME" ./install.sh --prefix="$CARGO_DIR" --disable-ldconfig
fi

export PATH="$CARGO_DIR/bin:$RACKET_DIR/bin:$PATH"
export PLTCOMPILEDROOTS="$HOME/aiu-compiled"

say "fetching Rust crates for the offline builds"
for m in "aiu-shell/shell" "AIU EDITOR/text-editor/editor" "AIU NOTATION/notation"; do
  run cargo fetch --locked --manifest-path "$ROOT/$m/Cargo.toml"
done

say "rewriting spec source paths to $ROOT"
SPECS="$(mktemp -d)"
mkdir -p "$SPECS/self"
if [ -x "$RACKET_DIR/bin/racket" ]; then
  "$RACKET_DIR/bin/racket" "$ROOT/AIU ECOSYSTEM/install/rewrite-specs.rkt" "$ROOT" "$ROOT/ecosystem-manifest" "$SPECS/all"
  cp "$SPECS/all/aiu-pm.rktd" "$SPECS/self/"
else
  say "dry run without racket: spec rewrite skipped"
fi

PMCLI="$ROOT/AIU-OS/AIU-PM/package-manager/src/entry/cli.rkt"
say "compiling the package manager (first run is slow)"
run "$RACKET_DIR/bin/raco" make -j "$JOBS" "$PMCLI"
say "pm installs itself"
run "$RACKET_DIR/bin/racket" "$PMCLI" apply "$SPECS/self" --confirm
say "pm installs the full ecosystem"
run "$RACKET_DIR/bin/racket" "$PMCLI" apply "$SPECS/all" --confirm

MARK="# aiu ecosystem"
if [ -z "$DRY" ] && ! grep -qF "$MARK" "$HOME/.profile" 2>/dev/null; then
  printf "%s\n" "$MARK" "export PATH=\"$CARGO_DIR/bin:$RACKET_DIR/bin:\$PATH\"" "for d in \"$DATA\"/aiu-pm/prefix/*/current/bin; do [ -d \"\$d\" ] && PATH=\"\$d:\$PATH\"; done" "export PATH" >> "$HOME/.profile"
  say "PATH lines added to ~/.profile (a nushell config needs the same PATH by hand)"
fi

SHELLBIN="$DATA/aiu-pm/prefix/aiu-shell/current/bin/aiu-shell"
if [ -n "$DRY" ]; then
  say "would set the login shell to $SHELLBIN"
elif [ -x "$SHELLBIN" ] && "$SHELLBIN" --version >/dev/null 2>&1; then
  if [ -w /etc/shells ]; then grep -qxF "$SHELLBIN" /etc/shells || printf "%s\n" "$SHELLBIN" >> /etc/shells; fi
  if command -v chsh >/dev/null 2>&1; then
    chsh -s "$SHELLBIN" || say "chsh failed: set the login shell to $SHELLBIN by hand"
  else
    say "no chsh here: set the login shell to $SHELLBIN by hand"
  fi
else
  say "aiu-shell is not installed or does not run: login shell unchanged"
fi
say "done. $WORK holds the downloaded sources and can be deleted"
