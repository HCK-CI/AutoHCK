# Re-enable the @driver_module@ PnP device after a memory leak check.

$ErrorActionPreference = 'Stop'
$driver = '@driver_module@'

$dev = Get-PnpDevice | Where-Object {
    $_.Status -ne 'OK' -and (
        ($_ | Get-PnpDeviceProperty -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data -eq $driver
    )
} | Select-Object -First 1

if (-not $dev) {
    Write-Output "FAIL: No disabled PnP device found for driver service '$driver'"
    exit 1
}

Write-Output "Enabling device: $($dev.FriendlyName) [$($dev.InstanceId)]"
Enable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false -ErrorAction SilentlyContinue

$timeout = 30
$elapsed = 0
while ($elapsed -lt $timeout) {
    $check = Get-PnpDevice -InstanceId $dev.InstanceId
    if ($check.Status -eq 'OK') {
        Write-Output "PASS: $driver device re-enabled ($($dev.FriendlyName))"
        exit 0
    }
    Start-Sleep -Seconds 3
    $elapsed += 3
}

$check = Get-PnpDevice -InstanceId $dev.InstanceId
Write-Output "FAIL: Device not active after enable (waited ${timeout}s): $($check.InstanceId) status=$($check.Status)"
exit 1
