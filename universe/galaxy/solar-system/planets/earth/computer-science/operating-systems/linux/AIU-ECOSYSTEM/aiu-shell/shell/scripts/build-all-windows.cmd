@echo off
echo -------------------------------------------------------------------
echo Building aiu-shell (nu.exe) and all the plugins
echo -------------------------------------------------------------------
echo.

echo Building aiu-shell.exe
cargo build --locked
echo.

call :build crates\aiu_shell_plugin_example aiu_shell_plugin_example.exe
call :build ..\..\crates\aiu_shell_plugin_gstat aiu_shell_plugin_gstat.exe
call :build ..\..\crates\aiu_shell_plugin_inc aiu_shell_plugin_inc.exe
call :build ..\..\crates\aiu_shell_plugin_query aiu_shell_plugin_query.exe
call :build ..\..\crates\aiu_shell_plugin_custom_values aiu_shell_plugin_custom_values.exe

cd ..\..
exit /b 0

:build
    setlocal
    set "location=%~1"
    set "target=%~2"

    cd "%location%"
    echo Building %target%
    cargo build
    echo.
    endlocal
exit /b 0
