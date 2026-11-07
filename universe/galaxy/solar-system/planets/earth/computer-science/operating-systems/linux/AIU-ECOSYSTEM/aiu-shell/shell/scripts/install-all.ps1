
# Usage: Just run `powershell install-all.ps1` in aiu-shell root directory

Write-Output "-----------------------------------------------------------------"
Write-Output "Installing aiu-shell (nu) and all the plugins"
Write-Output "-----------------------------------------------------------------"
Write-Output ""

Write-Output "Install aiu-shell from local..."
Write-Output "----------------------------------------------"
cargo install --force --path . --locked

$NU_PLUGINS = @(
    'aiu_shell_plugin_example',
    'aiu_shell_plugin_gstat',
    'aiu_shell_plugin_inc',
    'aiu_shell_plugin_query',
    'aiu_shell_plugin_custom_values',
    'aiu_shell_plugin_formats',
    'aiu_shell_plugin_polars'
)

foreach ( $plugin in $NU_PLUGINS) {
    Write-Output ''
    Write-Output "----------------------------------------------"
    Write-Output "Install plugin $plugin from local..."
    Write-Output "----------------------------------------------"
    Set-Location crates/$plugin
    cargo install --force --path .
    Set-Location ../../
}
