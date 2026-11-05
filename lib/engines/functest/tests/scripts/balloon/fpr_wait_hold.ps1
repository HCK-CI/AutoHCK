# fpr_wait_hold.ps1 - shared settle window: poll until the hold converges into the
# contract window (either counter at or below gate + hold margin, both at or above
# the floor). Used by fpr_optin_hold and fpr_release_under_pressure as a soft
# early-exit window; the verdict step is fpr_check_hold.ps1.
#
# Failure reporting follows the project convention: print "FAIL: ..." to stdout
# and exit 1 explicitly. Never a bare throw - over the winrm layer a terminating
# error kills the pipeline before the gem's trailing "if (!$?) { exit 1 }" runs,
# so the exit code defaults to 0 and the harness reports a false pass.
$ErrorActionPreference = 'Stop'

# Thresholds assume the driver's default floor/band derivation; explicit
# registry overrides (MinFreeMb/MinCommitMb/HysteresisMb) are not accounted.
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

$deadline = (Get-Date).AddSeconds(100)
while ($true) {
    Start-Sleep -Seconds 5
    $osx = Get-CimInstance Win32_OperatingSystem
    $a = [math]::Round($osx.FreePhysicalMemory / 1KB)
    $c = [math]::Round($osx.FreeVirtualMemory / 1KB)
    if (($a -ge $floor) -and ($c -ge $floor) -and
        (($a -le ($gate + $holdMarginMb)) -or ($c -le ($gate + $holdMarginMb)))) {
        break
    }
    if ((Get-Date) -ge $deadline) {
        Write-Output "FAIL: hold out of contract (avail $a MB, commit headroom $c MB, floor $floor MB, gate $gate MB, band $band MB) within 100s"
        exit 1
    }
}
Write-Output "PASS: hold settled (avail $a MB, commit headroom $c MB)"
