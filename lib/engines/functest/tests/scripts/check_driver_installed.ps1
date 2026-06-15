# Confirm @driver_module@ is present in the driver list before an update.

$ErrorActionPreference = 'Stop'

$d = (driverquery /fo csv | ConvertFrom-Csv) |
    Where-Object { $_.'Module Name' -eq '@driver_module@' }

if (-not $d) {
    throw 'Driver @driver_module@ not found - driver may not be installed'
}

Write-Output "Pre-update: $($d.'Display Name') is $($d.State)"
