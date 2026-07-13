# Find blnsvr.exe in the uploaded driver package and install the balloon service.

$ErrorActionPreference = 'Stop'

$blnsvr = Get-ChildItem -Recurse '@driver_dir@' -Filter blnsvr.exe |
    Select-Object -First 1

if (-not $blnsvr) {
    throw 'blnsvr.exe not found in driver package - check driver path'
}

Write-Output "Found: $($blnsvr.FullName)"
& $blnsvr.FullName -i
if ($LASTEXITCODE -ne 0) {
    throw "blnsvr.exe -i failed with exit code $LASTEXITCODE"
}
Write-Output 'Balloon service install command executed'
