# Confirm @driver_module@ is installed; outputs PASS: on success.

$ErrorActionPreference = 'Stop'

$d = (driverquery /fo csv | ConvertFrom-Csv) |
    Where-Object { $_.'Module Name' -eq '@driver_module@' }

if (-not $d) {
    throw 'Driver @driver_module@ not found - driver may not be installed'
}

Write-Output "PASS: @driver_module@ driver installed - $($d.'Display Name') is $($d.State)"
