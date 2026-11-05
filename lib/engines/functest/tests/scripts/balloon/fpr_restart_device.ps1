# Restart the balloon PnP device (disable + enable), polling for a clean state.
# The virtio-balloon PCI id depends on the host stack: legacy devices expose
# 1af4:1002, transitional 1af4:1045 and non-transitional 1af4:1052, so match
# all three forms instead of hardcoding one (the driver INF covers 1002/1045).
$ErrorActionPreference = 'Stop'

$dev = (Get-PnpDevice -PresentOnly | Where-Object {
          $_.InstanceId -like '*VEN_1AF4&DEV_1002*' -or
          $_.InstanceId -like '*VEN_1AF4&DEV_1045*' -or
          $_.InstanceId -like '*VEN_1AF4&DEV_1052*'
        } | Select-Object -First 1).InstanceId
if (-not $dev) { throw 'balloon PnP device (1af4:1002/1045/1052) not found' }

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
if ($status -ne 'OK') { throw "balloon device did not return to OK (current: $status)" }

Write-Output "PASS: balloon device restarted (status $status)"
