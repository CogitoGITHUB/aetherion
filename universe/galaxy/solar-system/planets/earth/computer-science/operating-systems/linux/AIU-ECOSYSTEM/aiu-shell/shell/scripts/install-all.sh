#!/usr/bin/env bash

set -euo pipefail

DIR=$(readlink -f $(dirname "${BASH_SOURCE[0]}"))
REPO_ROOT=$(dirname $DIR)

echo "-----------------------------------------------------------------"
echo "Installing aiu-shell (nu) and all the plugins"
echo "-----------------------------------------------------------------"
echo ""

echo "Install aiu-shell from local..."
echo "----------------------------------------------"
cargo install --force --path "$REPO_ROOT" --locked

NU_PLUGINS=(
    'aiu_shell_plugin_inc'
    'aiu_shell_plugin_gstat'
    'aiu_shell_plugin_query'
    'aiu_shell_plugin_example'
    'aiu_shell_plugin_custom_values'
    'aiu_shell_plugin_formats'
    'aiu_shell_plugin_polars'
)

for plugin in "${NU_PLUGINS[@]}"
do
    echo ''
    echo "----------------------------------------------"
    echo "Install plugin $plugin from local..."
    echo "----------------------------------------------"
    cargo install --force --path "$REPO_ROOT/crates/$plugin"
done
