# Verify BalloonService is registered and running. Starts it if stopped.

$ErrorActionPreference = 'Stop'

$svc = Get-Service -Name 'BalloonService' -ErrorAction SilentlyContinue

if (-not $svc) {
    throw 'BalloonService not found - install may have failed'
}

Write-Output "Service: $($svc.Name) - Status: $($svc.Status)"

if ($svc.Status -ne 'Running') {
    Start-Service BalloonService
}

$svc = Get-Service BalloonService
Write-Output "PASS: BalloonService is $($svc.Status)"
