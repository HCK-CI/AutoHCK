# Verify the @driver_module@ driver package catalog integrity using signtool.
# Validates .sys and .inf hashes match the .cat catalog — fails if signtool is missing.

$ErrorActionPreference = 'Stop'

$module = '@driver_module@'
$driverDir = '@driver_dir@'
$signtoolPath = '@signtool_path@'

if (-not (Test-Path $signtoolPath)) {
    throw "signtool not found at: $signtoolPath"
}

$sys = Get-ChildItem $driverDir -Filter "$module.sys" | Select-Object -First 1
if (-not $sys) { throw "$module.sys not found in $driverDir" }

$inf = Get-ChildItem $driverDir -Filter "$module.inf" | Select-Object -First 1
if (-not $inf) { throw "$module.inf not found in $driverDir" }

$catLine = Select-String -Path $inf.FullName -Pattern '^\s*CatalogFile\s*=' |
    Select-Object -First 1
if (-not $catLine) { throw "CatalogFile entry not found in $($inf.Name)" }

$catName = ($catLine.Line -replace '^\s*CatalogFile\s*=\s*', '').Trim()
$cat = Get-ChildItem $driverDir -Filter $catName | Select-Object -First 1
if (-not $cat) { throw "$catName not found in $driverDir" }

Write-Output "Using signtool: $signtoolPath"

$out = & $signtoolPath verify /v /pa /c $cat.FullName $sys.FullName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output ($out | Out-String)
    throw "signtool verify failed for $($sys.Name) against $($cat.Name)"
}
Write-Output "signtool: $($sys.Name) hash matches catalog"

$out = & $signtoolPath verify /v /pa /c $cat.FullName $inf.FullName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output ($out | Out-String)
    throw "signtool verify failed for $($inf.Name) against $($cat.Name)"
}
Write-Output "signtool: $($inf.Name) hash matches catalog"

Write-Output 'PASS: Driver package catalog cross-check verified'
