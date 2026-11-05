# No-hold assertion: with the feature off the guest keeps its free memory.
# A running hold settles at ~gate (floor + hysteresis) on either ledger;
# available and commit headroom both above 1.5x gate proves no hold is
# running. Thresholds derive from the RAM size.
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$availMb = [math]::Round($os.FreePhysicalMemory / 1KB)
$commitHeadroomMb = [math]::Round($os.FreeVirtualMemory / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band

if ($availMb -le 1.5 * $gate) {
    throw "available $availMb MB <= 1.5x gate $gate MB - a hold appears to be running"
}
if ($commitHeadroomMb -le 1.5 * $gate) {
    throw "commit headroom $commitHeadroomMb MB <= 1.5x gate $gate MB - a hold appears to be running on the commit ledger"
}
Write-Output "PASS: no hold running (available $availMb MB, commit headroom $commitHeadroomMb MB > 1.5x gate $gate MB)"
