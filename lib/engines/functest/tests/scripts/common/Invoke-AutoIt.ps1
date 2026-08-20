<#
.SYNOPSIS
    Locate AutoIt and run a .au3 script on the current desktop session.

.DESCRIPTION
    Intended to run inside an interactive session (e.g. after
    Invoke-InteractiveSession.ps1). Requires suite or case extra_software: ["autoit"].

    Usage: upload this script (and Invoke-InteractiveSession.ps1 if needed) from
    lib/engines/functest/tests/scripts/common/ via the case files_action step to
    e.g. C:\AutoHCK\common\, then invoke it from the interactive worker.

.PARAMETER Au3Path
    Absolute guest path to the .au3 script.

.PARAMETER TimeoutSec
    Max seconds to wait for AutoIt to exit (and optional -WaitForFile).

.PARAMETER WaitForFile
    If set, success requires this file to exist. The helper waits until
    AutoIt has exited and the file is present, or TimeoutSec elapses.

.PARAMETER ScriptArgs
    Extra arguments forwarded to the AutoIt script ($CmdLine[1] ...).

.PARAMETER MinimizeWindows
    Call Shell.Application MinimizeAll before starting AutoIt.

.PARAMETER LogPath
    Optional log file to append status lines to.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Au3Path,

    [int]$TimeoutSec = 180,

    [string]$WaitForFile = '',

    [string[]]$ScriptArgs = @(),

    [switch]$MinimizeWindows,

    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'

function Write-AutoItLog([string]$Text) {
    if ($LogPath) {
        Add-Content -Path $LogPath -Value $Text -Encoding ASCII
    }
}

function Get-AutoItPath {
    # Native x86 OS: AutoIt3_x64.exe does not exist and ProgramFiles(x86)
    # is empty, so skip both to avoid a hang/timeout.
    $isNativeX86 = ($env:PROCESSOR_ARCHITECTURE -eq 'x86') -and
        [string]::IsNullOrEmpty($env:PROCESSOR_ARCHITEW6432)

    if ($isNativeX86) {
        $candidates = @(
            "${env:ProgramFiles}\AutoIt3\AutoIt3.exe"
        )
    } else {
        $candidates = @(
            "${env:ProgramFiles}\AutoIt3\AutoIt3_x64.exe",
            "${env:ProgramFiles}\AutoIt3\AutoIt3.exe",
            "${env:ProgramFiles(x86)}\AutoIt3\AutoIt3_x64.exe",
            "${env:ProgramFiles(x86)}\AutoIt3\AutoIt3.exe"
        )
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

$autoIt = Get-AutoItPath
if (-not $autoIt) {
    Write-Output 'FAIL: AutoIt not found (suite or case extra_software autoit required)'
    exit 1
}
if (-not (Test-Path $Au3Path)) {
    Write-Output "FAIL: AutoIt script not found at $Au3Path"
    exit 1
}

if ($MinimizeWindows) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.MinimizeAll()
        Start-Sleep -Seconds 2
    } catch {
        Write-AutoItLog ("WARN: MinimizeAll failed: $($_.Exception.Message)")
    }
}

$argList = @('"' + $Au3Path + '"')
if ($ScriptArgs) { $argList += $ScriptArgs }
Write-AutoItLog ("Running: $autoIt $($argList -join ' ')")
$p = Start-Process -FilePath $autoIt -ArgumentList $argList -PassThru

$killedOnTimeout = $false
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    $null = $p.Refresh()
    if ($p.HasExited) {
        if (-not $WaitForFile -or (Test-Path $WaitForFile)) { break }
        # AutoIt already exited; keep polling for the output file until deadline.
    }
    Start-Sleep -Seconds 2
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-AutoItLog 'WARN: AutoIt still running after timeout; killed'
    $killedOnTimeout = $true
} else {
    Write-AutoItLog ("AutoIt exit code=$($p.ExitCode)")
}

if ($WaitForFile -and -not (Test-Path $WaitForFile)) {
    Write-Output "FAIL: expected output file not created: $WaitForFile"
    exit 1
}
if ($killedOnTimeout) {
    Write-Output "FAIL: AutoIt killed after timeout (${TimeoutSec}s)"
    exit 1
}
if ($p.ExitCode -ne 0) {
    Write-Output "FAIL: AutoIt exited $($p.ExitCode) ($Au3Path)"
    exit 1
}

Write-Output "PASS: AutoIt finished ($Au3Path)"
exit 0
