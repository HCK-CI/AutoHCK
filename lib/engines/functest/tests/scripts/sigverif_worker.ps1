<#
.SYNOPSIS
    Interactive-session worker: run sigverif via AutoIt and check @driver_module@.sys.

.DESCRIPTION
    Runs on the interactive desktop (via Invoke-InteractiveSession). Uploaded
    from the host via files_action; launched by run_sigverif_gui.ps1.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ModuleName
)

$ErrorActionPreference = 'Stop'

$driverSys = "$ModuleName.sys"
$sigverifLog = 'C:\Users\Public\Documents\SIGVERIF.TXT'
$au3 = 'C:\AutoHCK\sigverif.au3'
$autoItHelper = 'C:\AutoHCK\common\Invoke-AutoIt.ps1'
$workDir = 'C:\AutoHCK\sigverif_work'
$resultFile = Join-Path $workDir 'result.txt'
$workerLog = Join-Path $workDir 'worker.log'
$scanTimeoutSec = 900

function Write-Result([string]$Text, [int]$Code = 0) {
    Set-Content -Path $resultFile -Value $Text -Encoding ASCII
    Add-Content -Path $workerLog -Value $Text -Encoding ASCII
    exit $Code
}

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
Set-Content -Path $workerLog -Value ("worker start module=$ModuleName session=$((Get-Process -Id $PID).SessionId)") -Encoding ASCII

if (-not (Test-Path $autoItHelper)) {
    Write-Result "FAIL: AutoIt helper not found at $autoItHelper" 1
}

if (Test-Path $sigverifLog) {
    Remove-Item -Force $sigverifLog
    Add-Content -Path $workerLog -Value ("Removed previous log: $sigverifLog")
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $autoItHelper `
    -Au3Path $au3 `
    -TimeoutSec $scanTimeoutSec `
    -ScriptArgs $scanTimeoutSec `
    -WaitForFile $sigverifLog `
    -MinimizeWindows `
    -LogPath $workerLog
if ($LASTEXITCODE -ne 0) {
    Write-Result "FAIL: AutoIt/sigverif run failed (exit=$LASTEXITCODE)" 1
}

if (-not (Test-Path $sigverifLog)) {
    Write-Result ("FAIL: sigverif log not created: $sigverifLog") 1
}

$logText = Get-Content -Path $sigverifLog -Raw -ErrorAction Stop
Add-Content -Path $workerLog -Value ("--- SIGVERIF.TXT ($ModuleName lines) ---")
foreach ($line in ($logText -split [Environment]::NewLine)) {
    if ($line -match [regex]::Escape($ModuleName)) {
        Add-Content -Path $workerLog -Value $line
    }
}

function Test-SigverifSignedLine([string]$Line, [string]$DriverSys) {
    $esc = [regex]::Escape($DriverSys)
    # Complete filename token, not a substring of another filename.
    if ($Line -notmatch "(?i)(?<![A-Za-z0-9._-])$esc(?![A-Za-z0-9._-])") {
        return $false
    }
    if ($Line -match '(?i)\bNot\s+Signed\b') { return $false }
    if ($Line -match '(?i)\bUnsigned\b') { return $false }
    return ($Line -match '(?i)\bSigned\b')
}

$ok = $false
foreach ($line in ($logText -split [Environment]::NewLine)) {
    if (Test-SigverifSignedLine $line $driverSys) {
        $ok = $true
        Add-Content -Path $workerLog -Value ("Matched: $line")
        break
    }
}

Remove-Item -Force $sigverifLog -ErrorAction SilentlyContinue

if ($ok) {
    Write-Result ("PASS: $driverSys digitally signed per sigverif GUI scan") 0
}
Write-Result ("FAIL: $driverSys not reported as Signed in sigverif log") 1
