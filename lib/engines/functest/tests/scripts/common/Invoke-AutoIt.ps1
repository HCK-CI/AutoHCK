<#
.SYNOPSIS
    Locate AutoIt and run a .au3 script on the current desktop session.

.DESCRIPTION
    Intended to run inside an interactive session (e.g. after
    Invoke-InteractiveSession.ps1). Requires suite extra_software: ["autoit"].

    Usage: upload this script (and Invoke-InteractiveSession.ps1 if needed) from
    lib/engines/functest/tests/scripts/common/ via the case files_action step to
    e.g. C:\AutoHCK\common\, then invoke it from the interactive worker.

.PARAMETER Au3Path
    Absolute guest path to the .au3 script.

.PARAMETER TimeoutSec
    Max seconds to wait for AutoIt to exit (and optional -WaitForFile).

.PARAMETER WaitForFile
    If set, keep waiting until this file appears or TimeoutSec elapses
    (even after AutoIt exits). Success requires the file to exist.

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
    Write-Output 'FAIL: AutoIt not found (suite extra_software autoit required)'
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

Write-AutoItLog ("Running: $autoIt $Au3Path")
$p = Start-Process -FilePath $autoIt -ArgumentList ('"' + $Au3Path + '"') -PassThru

$killedOnTimeout = $false
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if ($WaitForFile -and (Test-Path $WaitForFile)) { break }
    if ($p.HasExited -and -not $WaitForFile) { break }
    # With -WaitForFile: keep polling until the file appears or deadline,
    # even if AutoIt has already exited.
    Start-Sleep -Seconds 2
}

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-AutoItLog 'WARN: AutoIt still running after timeout; killed'
    $killedOnTimeout = $true
} else {
    Write-AutoItLog ("AutoIt exit code=$($p.ExitCode)")
}

if ($WaitForFile) {
    if (-not (Test-Path $WaitForFile)) {
        Write-Output "FAIL: expected output file not created: $WaitForFile"
        exit 1
    }
} elseif ($killedOnTimeout) {
    Write-Output "FAIL: AutoIt killed after timeout (${TimeoutSec}s) with no -WaitForFile"
    exit 1
}

Write-Output "PASS: AutoIt finished ($Au3Path)"
exit 0
