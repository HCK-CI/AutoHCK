# Remove @driver_module@ from the Windows DriverStore using pnputil.

$ErrorActionPreference = 'Stop'

$drv = Get-WindowsDriver -Online |
    Where-Object { $_.OriginalFileName -like '*@driver_module@.inf' } |
    Select-Object -First 1

if (-not $drv) {
    throw 'Driver @driver_module@ not found in DriverStore'
}

Write-Output "Removing $($drv.Driver)"
pnputil /delete-driver $drv.Driver /uninstall /force
if ($LASTEXITCODE -ne 0) {
    throw "pnputil failed with exit code $LASTEXITCODE"
}
Write-Output 'Driver removed from store'
