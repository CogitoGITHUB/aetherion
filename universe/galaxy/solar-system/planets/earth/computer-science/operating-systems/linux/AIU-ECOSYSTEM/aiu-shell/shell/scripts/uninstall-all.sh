#!/usr/bin/env bash

set -euo pipefail

echo ''
echo "----------------------------------------------"
echo "Uninstall nu and all plugins from cargo/bin..."
echo "----------------------------------------------"

NU_PLUGINS=(
    'aiu_shell_plugin_inc'
    'aiu_shell_plugin_gstat'
    'aiu_shell_plugin_query'
    'aiu_shell_plugin_example'
    'aiu_shell_plugin_formats'
    'aiu_shell_plugin_custom_values'
    'aiu_shell_plugin_polars'
)

cargo uninstall nu
for plugin in "${NU_PLUGINS[@]}"
do
    cargo uninstall "$plugin"
done
