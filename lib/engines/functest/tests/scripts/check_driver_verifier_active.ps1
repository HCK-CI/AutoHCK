# Verify Driver Verifier is active for @driver_module@.sys.
# Used by memory_leak_check extension to fail early with a clear message
# when driver_verifier extension is missing or ordered incorrectly.

$ErrorActionPreference = 'Continue'
$driver = '@driver_module@'

$status = cmd /c "verifier /querysettings 2>&1" | Out-String
if ($status -notmatch [regex]::Escape($driver)) {
    throw @"
Driver Verifier is not active for $driver.sys — memory_leak_check requires it.
Use: --extensions memory_leak_check,driver_verifier
  (order matters: memory_leak_check must come BEFORE driver_verifier)
"@
}

Write-Output "PASS: Driver Verifier confirmed active for $driver.sys"
