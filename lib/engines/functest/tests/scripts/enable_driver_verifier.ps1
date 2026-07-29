# Enable Driver Verifier (standard flags) for @driver_module@.sys.
# Outputs PASS: on success; throws on failure.

$ErrorActionPreference = "Continue"
$driver = "@driver_module@"

cmd /c "verifier /standard /driver $driver.sys 2>&1"

$status = cmd /c "verifier /querysettings 2>&1" | Out-String
if ($status -notmatch [regex]::Escape($driver)) {
    throw "Driver Verifier not set for $driver after enable"
}

Write-Output "PASS: Driver Verifier enabled on $driver.sys"
