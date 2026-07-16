# Verify the VirtIO Balloon PnP device is present and in working order.

$ErrorActionPreference = 'Stop'

$d = Get-PnpDevice | Where-Object {
    $_.HardwareID -match 'VEN_1AF4&DEV_1002|VEN_1AF4&DEV_1045'
} | Select-Object -First 1

if (-not $d) {
    throw 'Balloon PnP device (VEN_1AF4 DEV_1002/1045) not found in device list'
}

if ($d.Status -ne 'OK') {
    throw "Balloon device found but not in OK state: $($d.Status) (Error code: $($d.ConfigManagerErrorCode))"
}

Write-Output "PASS: Balloon device found - $($d.FriendlyName) [$($d.Status)]"
