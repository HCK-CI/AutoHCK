# Verify the Authenticode signature on @driver_module@.sys in the DriverStore.
# Fails if the signature is missing or invalid.

$ErrorActionPreference = 'Stop'

$drv = Get-WindowsDriver -Online |
    Where-Object { $_.OriginalFileName -like '*@driver_module@.inf' } |
    Select-Object -First 1

if (-not $drv) { throw '@driver_module@.inf not found in the DriverStore' }

$drvDir = Split-Path $drv.OriginalFileName -Parent
$sys = Get-ChildItem $drvDir -Filter '@driver_module@.sys' | Select-Object -First 1

if (-not $sys) { throw '@driver_module@.sys not found in ' + $drvDir }

$sig = Get-AuthenticodeSignature $sys.FullName

Write-Output "Signature status: $($sig.Status)"
Write-Output "Signer: $($sig.SignerCertificate.Subject)"

if ($sig.Status -ne 'Valid') {
    throw '@driver_module@.sys is NOT signed (status: ' + $sig.Status + ')'
}

Write-Output 'PASS: Driver is digitally signed'
