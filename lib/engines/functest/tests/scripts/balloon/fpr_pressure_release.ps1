# Pressure assertion: allocate and touch more memory than the gate,
# then require that allocations keep succeeding and that available
# settles back above the floor.
# Whether a sample ever lands below the line is NOT asserted: with a fast
# release chain the crossings are exactly what the driver absorbs, so
# sampling can miss them.
# Thresholds assume the driver's default floor/band derivation; explicit
# registry overrides (MinFreeMb/MinCommitMb/HysteresisMb) are not accounted.
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band

# Pressure sizing: the sample that gates this run can read above the stop
# line (the guest keeps freeing memory between the driver's re-take ticks),
# and the crossing must be deep enough to outlast guest noise until the
# driver's watchdog observes it. A single hold margin covers both - the
# same engineering value check_no_hold uses above its gate: a standalone
# 256 MB constant, sized to the noise, deliberately not tracking the driver
# parameter.
$holdMarginMb = 256
$allocMb = $gate + $holdMarginMb

$chunks = New-Object System.Collections.ArrayList
$grown = 0
try {
    while ($grown -lt $allocMb) {
        $b = New-Object byte[] (64 * 1MB)
        for ($j = 0; $j -lt $b.Length; $j += 4096) { $b[$j] = 1 }
        [void]$chunks.Add($b)
        $grown += 64
    }
} catch {
    # the loop races the driver's release chain; an allocation failure here
    # means the guest ran out while being fed - report it explicitly ("FAIL:"
    # + exit 1) instead of surfacing as a raw exception the winrm gem would
    # turn into a false success
    Write-Output "FAIL: allocation failed during pressure (grown $grown of $allocMb MB): $($_.Exception.Message)"
    exit 1
}

# the release path may take a few seconds to settle back above the line;
# the touched chunks stay referenced until the measurement is done, so the
# recovery is not simply the pressure allocations being dropped - the
# references are not pinned, so this narrows the attribution rather than
# proving it
# the touched allocations consume both physical available and commit
# charge, so BOTH counters must be back above the floor for the answer to
# count - whichever binds first depends on the pagefile setup
$availMb = 0
$commitHeadMb = 0
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $osx = Get-CimInstance Win32_OperatingSystem
    $availMb = [math]::Round($osx.FreePhysicalMemory / 1KB)
    $commitHeadMb = [math]::Round($osx.FreeVirtualMemory / 1KB)
    if (($availMb -ge $floor) -and ($commitHeadMb -ge $floor)) { break }
    Start-Sleep -Seconds 2
}
$chunks.Clear()
$chunks = $null
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
if ($availMb -lt $floor) {
    Write-Output "FAIL: available $availMb MB stayed below the floor $floor MB after pressure"
    exit 1
}
if ($commitHeadMb -lt $floor) {
    Write-Output "FAIL: commit headroom $commitHeadMb MB stayed below the floor $floor MB after pressure"
    exit 1
}
Write-Output "PASS: pressure answered (allocated $allocMb MB, available $availMb MB, commit headroom $commitHeadMb MB, both >= floor $floor MB)"
