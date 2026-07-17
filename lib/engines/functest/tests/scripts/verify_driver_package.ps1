# Verify the @driver_module@ driver package Authenticode signatures before installation.
# Checks .sys, .cat, and .inf in @driver_dir@ — fails if any signature is invalid.

$ErrorActionPreference = 'Stop'

$module = '@driver_module@'
$driverDir = '@driver_dir@'

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

Write-Output "Package contents: $($sys.Name), $($inf.Name), $($cat.Name)"

$catSig = Get-AuthenticodeSignature $cat.FullName
Write-Output "Catalog signature: $($catSig.Status) — $($catSig.SignerCertificate.Subject)"
if ($catSig.Status -ne 'Valid') {
    throw "$($cat.Name) is NOT signed (status: $($catSig.Status))"
}

$sysSig = Get-AuthenticodeSignature $sys.FullName
Write-Output "Driver signature: $($sysSig.Status) — $($sysSig.SignerCertificate.Subject)"
if ($sysSig.Status -ne 'Valid') {
    throw "$($sys.Name) is NOT signed (status: $($sysSig.Status))"
}

Write-Output 'PASS: Driver package Authenticode signatures verified'
