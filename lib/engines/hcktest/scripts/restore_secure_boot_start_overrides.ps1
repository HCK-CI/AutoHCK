$ErrorActionPreference = 'Stop'
$statePath = 'C:\AutoHCK\SecureBootManual\start_overrides.clixml'
if (-not (Test-Path -LiteralPath $statePath)) { return }

$snapshot = Import-Clixml -LiteralPath $statePath
$originals = $snapshot.Originals
$controlSet = [int]$snapshot.ControlSet
if ($originals -isnot [hashtable] -or $controlSet -lt 1 -or $controlSet -gt 999 -or
    @($originals.Keys | Where-Object { $_ -notin @('iospy', 'MSDMFilt') }).Count -gt 0) {
    throw 'Invalid StartOverride snapshot'
}
$servicesPath = 'HKLM:\SYSTEM\ControlSet{0:D3}\Services' -f $controlSet
$failures = @()

foreach ($service in @('iospy', 'MSDMFilt')) {
    if (-not $originals.ContainsKey($service)) { continue }

    try {
        $original = $originals[$service]
        if ($original.KeyExisted -isnot [bool] -or $original.ValueExisted -isnot [bool] -or
            ($original.ValueExisted -and ($original.Value -isnot [int] -or -not $original.KeyExisted))) {
            throw 'Invalid saved value'
        }

        $servicePath = Join-Path $servicesPath $service
        if (-not (Test-Path -LiteralPath $servicePath)) { throw 'Service key disappeared' }
        $path = Join-Path $servicePath 'StartOverride'
        if ($original.ValueExisted) {
            if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
            New-ItemProperty -LiteralPath $path -Name '0' -Value $original.Value -PropertyType DWord -Force | Out-Null
        } elseif (Test-Path -LiteralPath $path) {
            $key = Get-Item -LiteralPath $path
            try {
                $valueExisted = $key.GetValueNames() -contains '0'
            } finally {
                $key.Close()
            }
            if ($valueExisted) { Remove-ItemProperty -LiteralPath $path -Name '0' }
        }

        if (-not $original.KeyExisted -and (Test-Path -LiteralPath $path)) {
            $key = Get-Item -LiteralPath $path
            try {
                if ($key.GetValueNames().Count -gt 0 -or $key.GetSubKeyNames().Count -gt 0) {
                    throw 'New StartOverride key is not empty'
                }
            } finally {
                $key.Close()
            }
            Remove-Item -LiteralPath $path -Force
        }

        $key = if (Test-Path -LiteralPath $path) { Get-Item -LiteralPath $path } else { $null }
        try {
            if (($null -ne $key) -ne $original.KeyExisted) { throw 'StartOverride key existence differs' }
            if ($original.ValueExisted) {
                if ($key.GetValueKind('0') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
                    [int]$key.GetValue('0') -ne $original.Value) { throw 'StartOverride value differs' }
            } elseif ($key -and $key.GetValueNames() -contains '0') {
                throw 'StartOverride value 0 still exists'
            }
        } finally {
            if ($key) { $key.Close() }
        }
    } catch {
        $failures += "$service`: $($_.Exception.Message)"
    }
}
if ($failures.Count -gt 0) { throw "Failed to restore StartOverride values: $($failures -join '; ')" }

# Keep the snapshot until both original states are verified.
Remove-Item -LiteralPath $statePath -Force
Write-Output 'Restored the original StartOverride state'
