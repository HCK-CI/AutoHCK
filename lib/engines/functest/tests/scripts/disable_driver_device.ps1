# Disable the @driver_module@ PnP device (unloads the driver).
# When Driver Verifier is active, unloading triggers pool tag verification —
# a pool leak causes a BSOD (bugcheck 0xC4).

$ErrorActionPreference = 'Stop'
$driver = '@driver_module@'

$dev = Get-PnpDevice | Where-Object {
    $_.Status -eq 'OK' -and (
        ($_ | Get-PnpDeviceProperty -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue).Data -eq $driver
    )
} | Select-Object -First 1

if (-not $dev) {
    throw "No active PnP device found for driver service '$driver'"
}

Write-Output "Disabling device: $($dev.FriendlyName) [$($dev.InstanceId)]"
Disable-PnpDevice -InstanceId $dev.InstanceId -Confirm:$false

$check = Get-PnpDevice -InstanceId $dev.InstanceId
if ($check.Status -eq 'OK') {
    throw "Device still active after disable: $($check.InstanceId)"
}

Write-Output "PASS: $driver device disabled ($($dev.FriendlyName))"
