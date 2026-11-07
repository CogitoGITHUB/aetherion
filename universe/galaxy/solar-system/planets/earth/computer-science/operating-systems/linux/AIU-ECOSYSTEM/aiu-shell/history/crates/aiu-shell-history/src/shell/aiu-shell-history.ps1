# aiu-shell-history PowerShell module
#
# This should support PowerShell 5.1 (which is shipped with Windows) and later versions, on Windows and Linux.
#
# Usage: aiu-shell-history init powershell | Out-String | Invoke-Expression
#
# Settings:
# - $env:AIU_SHELL_HISTORY_POWERSHELL_PROMPT_OFFSET - Number of lines to offset the prompt position after exiting search.
#   This is useful when using a multi-line prompt: e.g. set this to -1 when using a 2-line prompt.
#   It is initialized from the current prompt line count if not set when the first aiu-shell-history search is performed.

if (Get-Module aiu-shell-history -ErrorAction Ignore) {
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Warning "The aiu-shell-history module is already loaded, replacing it."
        Remove-Module aiu-shell-history
    } else {
        Write-Warning "The aiu-shell-history module is already loaded, skipping."
        return
    }
}

if (!(Get-Command aiu-shell-history -ErrorAction Ignore)) {
    Write-Error "The 'aiu-shell-history' executable needs to be available in the PATH."
    return
}

if (!(Get-Module PSReadLine -ErrorAction Ignore)) {
    Write-Error "aiu-shell-history requires the PSReadLine module to be installed."
    return
}

New-Module -Name aiu-shell-history -ScriptBlock {
    if (-not $env:AIU_SHELL_HISTORY_SESSION -or $env:AIU_SHELL_HISTORY_PID -ne $PID) {
        $env:AIU_SHELL_HISTORY_SESSION = aiu-shell-history uuid
        $env:AIU_SHELL_HISTORY_PID = $PID
    }

    $script:aiu-shell-historyHistoryId = $null
    $script:previousPSConsoleHostReadLine = $Function:PSConsoleHostReadLine

    # The ReadLine overloads changed with breaking changes over time, make sure the one we expect is available.
    $script:hasExpectedReadLineOverload = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine).OverloadDefinitions.Contains("static string ReadLine(runspace runspace, System.Management.Automation.EngineIntrinsics engineIntrinsics, System.Threading.CancellationToken cancellationToken, System.Nullable[bool] lastRunStatus)")

    function Get-CommandLine {
        $commandLine = ""
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$commandLine, [ref]$null)
        return $commandLine
    }

    function Set-CommandLine {
        param([string]$Text)

        $commandLine = Get-CommandLine
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $commandLine.Length, $Text)
    }

    # This function name is called by PSReadLine to read the next command line to execute.
    # We replace it with a custom implementation which adds aiu-shell-history support.
    function PSConsoleHostReadLine {
        ## 1. Collect the exit code of the previous command.

        # This needs to be done as the first thing because any script run will flush $?.
        $lastRunStatus = $?

        # Exit statuses are maintained separately for native and PowerShell commands, this needs to be taken into account.
        $lastNativeExitCode = $global:LASTEXITCODE
        $exitCode = if ($lastRunStatus) { 0 } elseif ($lastNativeExitCode) { $lastNativeExitCode } else { 1 }

        ## 2. Report the status of the previous command to aiu-shell-history (aiu-shell-history history end).

        if ($script:aiu-shell-historyHistoryId) {
            try {
                # The duration is not recorded in old PowerShell versions, let aiu-shell-history handle it. $null arguments are ignored.
                $duration = (Get-History -Count 1).Duration.Ticks * 100
                $durationArg = if ($duration) { "--duration=$duration" } else { $null }

                # Fire and forget the aiu-shell-history history end command to avoid blocking the shell during a potential sync.
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo.FileName = "aiu-shell-history"
                $process.StartInfo.Arguments = "history end --exit=$exitCode $durationArg -- $script:aiu-shell-historyHistoryId"
                $process.StartInfo.UseShellExecute = $false
                $process.StartInfo.CreateNoWindow = $true
                $process.StartInfo.RedirectStandardInput = $true
                $process.StartInfo.RedirectStandardOutput = $true
                $process.StartInfo.RedirectStandardError = $true
                $process.Start() | Out-Null
                $process.StandardInput.Close()
                $process.BeginOutputReadLine()
                $process.BeginErrorReadLine()
            }
            catch {
                # Ignore errors to avoid breaking the shell.
                # An error would occur if the user removes aiu-shell-history from the PATH, for instance.
            }
            finally {
                $script:aiu-shell-historyHistoryId = $null
            }
        }

        ## 3. Read the next command line to execute.

        # PSConsoleHostReadLine implementation from PSReadLine, adjusted to support old versions.
        Microsoft.PowerShell.Core\Set-StrictMode -Off

        $line = if ($script:hasExpectedReadLineOverload) {
            # When the overload we expect is available, we can pass $lastRunStatus to it.
            [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, [System.Threading.CancellationToken]::None, $lastRunStatus)
        } else {
            # Either PSReadLine is older than v2.2.0-beta3, or maybe newer than we expect, so use the function from PSReadLine as-is.
            & $script:previousPSConsoleHostReadLine
        }

        ## 4. Report the next command line to aiu-shell-history (aiu-shell-history history start).

        # PowerShell doesn't handle double quotes in native command line arguments the same way depending on its version,
        # and the value of $PSNativeCommandArgumentPassing - see the about_Parsing help page which explains the breaking changes.
        # This makes it unreliable, so we go through an environment variable, which should always be consistent across versions.
        try {
            $env:AIU_SHELL_HISTORY_COMMAND_LINE = $line
            $script:aiu-shell-historyHistoryId = aiu-shell-history history start --command-from-env
        }
        catch {
            # Ignore errors to avoid breaking the shell, see above.
        }
        finally {
            $env:AIU_SHELL_HISTORY_COMMAND_LINE = $null
        }

        $global:LASTEXITCODE = $lastNativeExitCode
        return $line
    }

    function Invoke-AiuShellHistorySearch {
        param([string]$ExtraArgs = "")

        $previousOutputEncoding = [System.Console]::OutputEncoding
        $resultFile = New-TemporaryFile
        $suggestion = ""
        $errorOutput = ""

        try {
            [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

            # Start-Process does some crazy stuff, just use the Process class directly to have more control.
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo.FileName = "aiu-shell-history"
            $process.StartInfo.Arguments = "search -i --result-file ""$($resultFile.FullName)"" $ExtraArgs"
            $process.StartInfo.UseShellExecute = $false
            $process.StartInfo.RedirectStandardError = $true
            $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            $process.StartInfo.EnvironmentVariables["AIU_SHELL_HISTORY_SHELL"] = "powershell"
            $process.StartInfo.EnvironmentVariables["AIU_SHELL_HISTORY_QUERY"] = Get-CommandLine
            # PowerShell's Set-Location (cd) doesn't update the process-level working directory, set it explicitly
            $process.StartInfo.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath

            try {
                $process.Start() | Out-Null

                # A single stream is redirected, so we can read it synchronously, but we have to start reading it
                # before waiting for the process to exit, otherwise the buffer could fill up and cause a deadlock.
                $errorOutput = $process.StandardError.ReadToEnd().Trim()
                $process.WaitForExit()

                $suggestion = (Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | Out-String).Trim()
            }
            catch {
                $errorOutput = $_
            }

            if ($errorOutput) {
                Write-Host -ForegroundColor Red "aiu-shell-history error:"
                Write-Host -ForegroundColor DarkRed $errorOutput
            }

            # If no shell prompt offset is set, initialize it from the current prompt line count.
            if ($null -eq $env:AIU_SHELL_HISTORY_POWERSHELL_PROMPT_OFFSET) {
                try {
                    $promptLines = (& $Function:prompt | Out-String | Measure-Object -Line).Lines
                    $env:AIU_SHELL_HISTORY_POWERSHELL_PROMPT_OFFSET = -1 * ($promptLines - 1)
                }
                catch {
                    $env:AIU_SHELL_HISTORY_POWERSHELL_PROMPT_OFFSET = 0
                }
            }

            # PSReadLine maintains its own cursor position, which will no longer be valid if aiu-shell-history scrolls the display in inline mode.
            # Fortunately, InvokePrompt can receive a new Y position and reset the internal state.
            $y = $Host.UI.RawUI.CursorPosition.Y + [int]$env:AIU_SHELL_HISTORY_POWERSHELL_PROMPT_OFFSET
            $y = [System.Math]::Max([System.Math]::Min($y, [System.Console]::BufferHeight - 1), 0)
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, $y)

            if ($suggestion -eq "") {
                # The previous input was already rendered by InvokePrompt
                return
            }

            $acceptPrefix = "__aiu_shell_history_accept__:"

            if ( $suggestion.StartsWith($acceptPrefix)) {
                Set-CommandLine $suggestion.Substring($acceptPrefix.Length)
                [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            } else {
                Set-CommandLine $suggestion
            }
        }
        finally {
            [System.Console]::OutputEncoding = $previousOutputEncoding
            $resultFile.Delete()
        }
    }

    function Enable-AiuShellHistorySearchKeys {
        param([bool]$CtrlR = $true, [bool]$UpArrow = $true)

        if ($CtrlR) {
            Set-PSReadLineKeyHandler -Chord "Ctrl+r" -BriefDescription "Runs aiu-shell-history search" -ScriptBlock {
                Invoke-AiuShellHistorySearch
            }
        }

        if ($UpArrow) {
            Set-PSReadLineKeyHandler -Chord "UpArrow" -BriefDescription "Runs aiu-shell-history search" -ScriptBlock {
                $line = Get-CommandLine

                if (!$line.Contains("`n")) {
                    Invoke-AiuShellHistorySearch -ExtraArgs "--shell-up-key-binding"
                } else {
                    [Microsoft.PowerShell.PSConsoleReadLine]::PreviousLine()
                }
            }
        }
    }

    $ExecutionContext.SessionState.Module.OnRemove += {
        $env:AIU_SHELL_HISTORY_SESSION = $null
        $Function:PSConsoleHostReadLine = $script:previousPSConsoleHostReadLine
    }

    Export-ModuleMember -Function @("Enable-AiuShellHistorySearchKeys", "PSConsoleHostReadLine")
} | Import-Module -Global
