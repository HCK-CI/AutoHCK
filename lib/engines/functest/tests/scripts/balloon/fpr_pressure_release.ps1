# Pressure assertion: allocate and touch more memory than the whole
# hysteresis window. The driver must keep the allocation succeeding (the
# release path answers the pressure) and available must settle back above
# the floor.
# Whether a sample ever lands below the line is NOT asserted: with a fast
# release chain the crossings are exactly what the driver absorbs, so
# sampling can miss them.
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band
$allocMb = $gate + $band + 256

$chunks = New-Object System.Collections.ArrayList
$grown = 0
while ($grown -lt $allocMb) {
    $b = New-Object byte[] (64 * 1MB)
    for ($j = 0; $j -lt $b.Length; $j += 4096) { $b[$j] = 1 }
    [void]$chunks.Add($b)
    $grown += 64
}

# the release path may take a few seconds to settle back above the line;
# the touched chunks stay referenced until the measurement is done so the
# recovery cannot be attributed to reclaiming the pressure allocations
$availMb = 0
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    $availMb = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
    if ($availMb -ge $floor) { break }
    Start-Sleep -Seconds 2
}
$chunks.Clear()
if ($availMb -lt $floor) {
    throw "available $availMb MB stayed below the floor $floor MB after pressure"
}
Write-Output "PASS: pressure answered (allocated $allocMb MB, available $availMb MB >= floor $floor MB)"
