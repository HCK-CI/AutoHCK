$ErrorActionPreference = 'Stop'
$directory = 'C:\AutoHCK\SecureBootManual'
$statePath = Join-Path $directory 'start_overrides.clixml'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
if (Test-Path -LiteralPath $statePath) {
    throw 'An earlier StartOverride snapshot still needs restoration'
}

$controlSet = [int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Select' -Name Current).Current
$servicesPath = 'HKLM:\SYSTEM\ControlSet{0:D3}\Services' -f $controlSet
$originals = @{}
foreach ($service in @('iospy', 'MSDMFilt')) {
    $servicePath = Join-Path $servicesPath $service
    if (-not (Test-Path -LiteralPath $servicePath)) { continue }

    $path = Join-Path $servicePath 'StartOverride'
    $key = if (Test-Path -LiteralPath $path) { Get-Item -LiteralPath $path } else { $null }
    try {
        $valueExisted = $key -and $key.GetValueNames() -contains '0'
        if ($valueExisted -and $key.GetValueKind('0') -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            throw "$service StartOverride value 0 is not a REG_DWORD"
        }
        $originals[$service] = [pscustomobject]@{
            KeyExisted = [bool]$key
            ValueExisted = [bool]$valueExisted
            Value = if ($valueExisted) { [int]$key.GetValue('0') } else { $null }
        }
    } finally {
        if ($key) { $key.Close() }
    }
}
if ($originals.Count -eq 0) { return }

# Save both originals before changing either value.
$snapshot = [pscustomobject]@{ ControlSet = $controlSet; Originals = $originals }
$snapshot | Export-Clixml -LiteralPath "$statePath.tmp" -Force
Move-Item -LiteralPath "$statePath.tmp" -Destination $statePath -Force

foreach ($service in @('iospy', 'MSDMFilt')) {
    if (-not $originals.ContainsKey($service)) { continue }

    $path = Join-Path (Join-Path $servicesPath $service) 'StartOverride'
    if (-not (Test-Path -LiteralPath (Join-Path $servicesPath $service))) {
        throw "Service key disappeared before setting $service StartOverride"
    }
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name '0' -Value 3 -PropertyType DWord -Force | Out-Null
}

Write-Output 'Saved and set available StartOverride values'
