<#
.SYNOPSIS
    Hop from Session 0 to the interactive desktop and run a worker script.

.DESCRIPTION
    Functest guest_run / guest_run_file often execute in Session 0, where GUI
    automation (AutoIt, etc.) cannot attach to the user desktop. This helper
    registers a Scheduled Task with LogonType Interactive, starts it as the
    AutoHCK autologin user, and waits for a result file.

    Any GUI / AutoIt functest can reuse this; keep test-specific logic in the
    worker script pointed at by -ScriptPath.

    Usage: upload helpers from lib/engines/functest/tests/scripts/common/ via
    the case files_action step to e.g. C:\AutoHCK\common\, then call this
    script from the Session-0 launcher (see driver_sigverif).

.PARAMETER ScriptPath
    Absolute guest path to the worker .ps1 (uploaded via files_action).

.PARAMETER ArgumentList
    Extra arguments appended after powershell -File <ScriptPath>.

.PARAMETER TaskName
    Scheduled Task name. Must be unique per concurrent test/client (use an
    AutoHCK_ prefix plus a test-specific suffix, e.g. AutoHCK_Sigverif) so
    overlapping runs do not unregister each other's tasks.

.PARAMETER ResultFile
    Absolute path the worker writes; first line should be PASS:... or FAIL:...

.PARAMETER TimeoutSec
    Seconds to wait for ResultFile before failing.

.PARAMETER WorkDir
    Working directory created before the task starts.

.PARAMETER WorkerLog
    Optional log path to dump on success/timeout (if present).
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [string]$ArgumentList = '',

    [string]$TaskName = 'AutoHCK_Interactive',

    [Parameter(Mandatory = $true)]
    [string]$ResultFile,

    [int]$TimeoutSec = 240,

    [string]$WorkDir = 'C:\AutoHCK\interactive_work',

    [string]$WorkerLog = ''
)

$ErrorActionPreference = 'Stop'

function Get-InteractiveUser {
    # AutoHCK autologin: Winlogon DefaultUserName names the interactive user.
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $autoUser = (Get-ItemProperty -Path $winlogon -Name 'DefaultUserName' -ErrorAction SilentlyContinue).DefaultUserName
    if ($autoUser) { return $autoUser }
    return 'Administrator'
}

if (-not (Test-Path $ScriptPath)) {
    Write-Output "FAIL: worker script not found at $ScriptPath (files_action upload required)"
    exit 1
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Remove-Item -Force $ResultFile -ErrorAction SilentlyContinue
if ($WorkerLog) {
    Remove-Item -Force $WorkerLog -ErrorAction SilentlyContinue
}

$user = Get-InteractiveUser
Write-Output "Outer session=$((Get-Process -Id $PID).SessionId); launching interactive user='$user'"
Write-Output "Worker: $ScriptPath"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
if ($ArgumentList) {
    $arg = "$arg $ArgumentList"
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Output "Started scheduled task '$TaskName'; waiting for result..."

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $ResultFile) {
        $text = (Get-Content -Path $ResultFile -Raw).Trim()
        Write-Output $text
        if ($WorkerLog -and (Test-Path $WorkerLog)) {
            Write-Output '--- worker.log ---'
            Get-Content -Path $WorkerLog | ForEach-Object { Write-Output $_ }
        }
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        if ($text -like 'PASS:*') { exit 0 }
        exit 1
    }
    Start-Sleep -Seconds 2
}

Write-Output "FAIL: timed out waiting for interactive worker result ($TaskName)"
if ($WorkerLog -and (Test-Path $WorkerLog)) {
    Write-Output '--- worker.log ---'
    Get-Content -Path $WorkerLog | ForEach-Object { Write-Output $_ }
}
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
exit 1
