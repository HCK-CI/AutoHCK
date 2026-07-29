# Disable Driver Verifier and confirm it is no longer set for @driver_module@.sys.
# Outputs PASS: on success; throws on failure.

$ErrorActionPreference = "Continue"
$driver = "@driver_module@"

cmd /c "verifier /reset 2>&1"

$status = cmd /c "verifier /querysettings 2>&1" | Out-String
if ($status -match [regex]::Escape($driver)) {
    throw "Driver Verifier still set for $driver after disable"
}

Write-Output "PASS: Driver Verifier disabled for $driver.sys"
