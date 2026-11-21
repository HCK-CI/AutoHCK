# No-hold assertion: with the feature off the guest keeps its free memory.
# A running hold keeps a memory counter at ~gate; the guest can free memory
# between the driver's re-take ticks so a sample can read above the gate
# by ordinary guest noise. Reading above gate + hold margin on BOTH
# counters is consistent with no hold running (the same margin check_hold
# uses on the other side of that line to flag one as running). Thresholds derive
# from the RAM size.
# Thresholds assume the driver's default floor/band derivation; explicit
# registry overrides (MinFreeMb/MinCommitMb/HysteresisMb) are not accounted.
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$availMb = [math]::Round($os.FreePhysicalMemory / 1KB)
$commitHeadroomMb = [math]::Round($os.FreeVirtualMemory / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band
# Hold margin: an engineering value - how far a clean sample must sit
# above the gate to count as "no hold running". 256 MB is a standalone
# engineering constant: it is the same magnitude as the band's clamp
# lower bound, sized to the noise, and deliberately does not track the
# driver parameter.
$holdMarginMb = 256
$cleanLine = $gate + $holdMarginMb

if ($availMb -le $cleanLine) {
    Write-Output "FAIL: available $availMb MB <= gate+margin $cleanLine MB - a hold appears to be running"
    exit 1
}
if ($commitHeadroomMb -le $cleanLine) {
    Write-Output "FAIL: commit headroom $commitHeadroomMb MB <= gate+margin $cleanLine MB - a hold appears to be running on the commit side"
    exit 1
}
Write-Output "PASS: no hold running (available $availMb MB, commit headroom $commitHeadroomMb MB > gate+margin $cleanLine MB)"
