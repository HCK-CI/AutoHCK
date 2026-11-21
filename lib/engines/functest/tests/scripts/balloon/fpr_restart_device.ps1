# Restart the balloon PnP device (disable + enable), polling for a clean state.
# Match the two ids the driver INF binds: legacy 1af4:1002 and modern
# 1af4:1045. -PresentOnly is required - without it a stale devnode left by an
# earlier VM topology can be selected and Disable-PnpDevice fails on it.
# Failure reporting: "FAIL: ..." + explicit exit 1 - never a bare throw,
# which the winrm gem turns into a false success (see fpr_wait_hold.ps1).
$ErrorActionPreference = 'Stop'

$dev = (Get-PnpDevice -PresentOnly | Where-Object {
          $_.InstanceId -like '*VEN_1AF4&DEV_1002*' -or
          $_.InstanceId -like '*VEN_1AF4&DEV_1045*'
        } | Select-Object -First 1).InstanceId
if (-not $dev) {
    Write-Output 'FAIL: balloon PnP device (1af4:1002/1045) not found'
    exit 1
}

Disable-PnpDevice -InstanceId $dev -Confirm:$false
Start-Sleep -Milliseconds 500
Enable-PnpDevice -InstanceId $dev -Confirm:$false

$status = $null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $status = (Get-PnpDevice -InstanceId $dev).Status
    if ($status -eq 'OK') { break }
    Start-Sleep -Seconds 1
}
if ($status -ne 'OK') {
    Write-Output "FAIL: balloon device did not return to OK (current: $status)"
    exit 1
}

Write-Output "PASS: balloon device restarted (status $status)"
