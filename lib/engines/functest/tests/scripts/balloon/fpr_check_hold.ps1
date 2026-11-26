# Held assertion: with the feature on, the hold stops when EITHER memory
# counter reaches its gate - available (physical memory) or commit
# headroom. Which one binds first depends on the pagefile setup. The
# gate is where the hold stops, not a defended line: after the hold stops,
# ordinary guest noise (each WinRM step runs in a fresh PowerShell
# process) can dip the bound counter into the hysteresis band [floor,
# gate) where the driver stays quiet by design. The defended limit is
# the floor. So the assertion checks: (1) neither counter is below the
# floor (the hard guarantee) and (2) at least one counter sits at or
# below the gate plus the hold margin (the hold really converged there).
# Thresholds assume the driver's default floor/band derivation; explicit
# registry overrides (MinFreeMb/MinCommitMb/HysteresisMb) are not accounted.
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band
# Hold margin: how far a sample can read above the gate. The guest keeps
# freeing memory between the driver's re-take ticks, so a fresh sample can
# be above the gate by ordinary guest noise. 256 MB is a standalone
# engineering constant: it is the same magnitude as the band's clamp
# lower bound, sized to the noise, and deliberately does not track the
# driver parameter.
$holdMarginMb = 256

$deadline = (Get-Date).AddSeconds(50)
$availMb = -1
$commitHeadMb = -1
while ($true) {
    $osx = Get-CimInstance Win32_OperatingSystem
    $availMb = [math]::Round($osx.FreePhysicalMemory / 1KB)
    $commitHeadMb = [math]::Round($osx.FreeVirtualMemory / 1KB)
    $ok = ($availMb -ge $floor) -and ($commitHeadMb -ge $floor) -and
          (($availMb -le ($gate + $holdMarginMb)) -or ($commitHeadMb -le ($gate + $holdMarginMb)))
    if ($ok) { break }
    if ((Get-Date) -ge $deadline) {
        Write-Output "FAIL: hold out of contract (available $availMb MB, commit headroom $commitHeadMb MB, floor $floor MB, gate $gate MB, band $band MB)"
        exit 1
    }
    Start-Sleep -Seconds 5
}
Write-Output "PASS: hold in contract (available $availMb MB, commit headroom $commitHeadMb MB, floor $floor MB, gate $gate MB, band $band MB)"
