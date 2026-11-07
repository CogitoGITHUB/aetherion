#!/usr/bin/env bash

set -euo pipefail

DIR=$(readlink -f $(dirname "${BASH_SOURCE[0]}"))
REPO_ROOT=$(dirname $DIR)

echo "---------------------------------------------------------------"
echo "Building aiu-shell (nu) and all the plugins"
echo "---------------------------------------------------------------"
echo ""

NU_PLUGINS=(
    'aiu_shell_plugin_example'
    'aiu_shell_plugin_gstat'
    'aiu_shell_plugin_inc'
    'aiu_shell_plugin_query'
    'aiu_shell_plugin_custom_values'
    'aiu_shell_plugin_polars'
)

echo "Building aiu-shell"
(
    cd $REPO_ROOT
    cargo build --locked
)

for plugin in "${NU_PLUGINS[@]}"
do
    echo "Building $plugin..."
    echo "-----------------------------"
    (
        cd "$REPO_ROOT/crates/$plugin"
        cargo build
    )
done
