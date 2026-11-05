# Held assertion: with the feature on, the hold stops when EITHER ledger
# reaches its gate - the physical ledger (available memory) or the commit
# ledger (commit headroom). Which one binds first depends on the pagefile
# setup. The gate is a stop line, not a defended line: after the hold
# stops, ordinary guest noise (each WinRM step runs in a fresh PowerShell
# process) can dip the bound ledger into the hysteresis zone [floor, gate)
# where the driver stays quiet by design. The defended limit is the floor.
# So the assertion checks: (1) neither ledger is below the floor (the
# hard guarantee) and (2) at least one ledger sits at or below the gate
# plus the band (the hold really converged there).
$ErrorActionPreference = 'Stop'

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
$floor = [math]::Max([math]::Round($totalMb / 16), 128)
$band = [math]::Min([math]::Max([math]::Round($totalMb / 32), 256), 1024)
$gate = $floor + $band

function Send-Beacon($a, $c, $tag) {
    try {
        $t = New-Object System.Net.Sockets.TcpClient
        $t.Connect('192.168.100.1', 9999)
        $s = $t.GetStream()
        $b = [Text.Encoding]::ASCII.GetBytes("$tag avail=$a commit=$c floor=$floor gate=$gate band=$band")
        $s.Write($b, 0, $b.Length)
        $s.Close(); $t.Close()
    } catch { }
}

$deadline = (Get-Date).AddSeconds(50)
$availMb = -1
$commitHeadMb = -1
while ($true) {
    $osx = Get-CimInstance Win32_OperatingSystem
    $availMb = [math]::Round($osx.FreePhysicalMemory / 1KB)
    $commitHeadMb = [math]::Round($osx.FreeVirtualMemory / 1KB)
    $ok = ($availMb -ge ($floor - 8)) -and ($commitHeadMb -ge ($floor - 8)) -and
          (($availMb -le ($gate + $band)) -or ($commitHeadMb -le ($gate + $band)))
    if ($ok) { break }
    if ((Get-Date) -ge $deadline) {
        Send-Beacon $availMb $commitHeadMb 'check_hold_FAIL'
        throw "hold out of contract (available $availMb MB, commit headroom $commitHeadMb MB, floor $floor MB, gate $gate MB, band $band MB)"
    }
    Start-Sleep -Seconds 5
}
Send-Beacon $availMb $commitHeadMb 'check_hold_PASS'
Write-Output "PASS: hold in contract (available $availMb MB, commit headroom $commitHeadMb MB, floor $floor MB, gate $gate MB, band $band MB)"
