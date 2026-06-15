# Locate @driver_module@.sys in the Windows DriverStore.
# Fails if the driver is not installed.

$ErrorActionPreference = 'Stop'

$drv = Get-WindowsDriver -Online |
    Where-Object { $_.OriginalFileName -like '*@driver_module@.inf' } |
    Select-Object -First 1

if (-not $drv) {
    throw '@driver_module@ driver not found in DriverStore - driver may not be installed'
}

$drvDir = Split-Path $drv.OriginalFileName -Parent
$sys = Get-ChildItem $drvDir -Filter '@driver_module@.sys' -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $sys) {
    throw '@driver_module@.sys not found in DriverStore at ' + $drvDir
}

Write-Output "Found: $($sys.FullName)"
