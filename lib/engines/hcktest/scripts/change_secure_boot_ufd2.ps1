# Called locally by AutoIt for "Change UFD #2 to use msft_test_pressanykey.efi".
# The existing USB filesystem is reused; this script never formats a disk.
$ErrorActionPreference = 'Stop'
$statePath = 'C:\AutoHCK\SecureBootManual\ufd2_msft.json'
Start-Transcript -Path 'C:\AutoHCK\SecureBootManual\change_ufd2.log' -Append | Out-Null

try {
    $disks = @(Get-Disk | Where-Object {
        ([string]$_.SerialNumber -replace '\s', '').ToUpperInvariant() -eq 'SVVPUFD2'
    })
    if ($disks.Count -ne 1) {
        throw "Expected one disk with serial SVVPUFD2; found $($disks.Count)"
    }
    $disk = $disks[0]
    if ([string]$disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or
        $disk.IsOffline -or $disk.IsReadOnly) {
        throw 'SVVPUFD2 is not an available writable USB data disk'
    }
    $partitions = @(Get-Partition -DiskNumber $disk.Number)
    if ($partitions.Count -ne 1 -or -not $partitions[0].DriveLetter) {
        throw 'SVVPUFD2 must have one partition with a drive letter'
    }
    $volumes = @(Get-Volume -Partition $partitions[0])
    if ($volumes.Count -ne 1 -or $volumes[0].FileSystem -ne 'FAT32' -or
        $volumes[0].FileSystemLabel -ne 'UFD #2') {
        throw 'SVVPUFD2 must be the prepared FAT32 volume labelled UFD #2'
    }

    $bootDirectory = Join-Path ([string]$partitions[0].DriveLetter + ':\') 'EFI\BOOT'
    $source = Join-Path $bootDirectory 'msft_test_pressanykey.efi'
    $destination = Join-Path $bootDirectory 'bootx64.efi'
    $backup = Join-Path $bootDirectory 'bootx64.efi.autohck-backup'

    # Record both hashes before the first rename. If the watcher restarts
    # before clicking OK, verify/resume the same change.
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.Serial -ne 'SVVPUFD2' -or $state.OriginalHash -notmatch '^[0-9A-F]{64}$' -or
            $state.ReplacementHash -notmatch '^[0-9A-F]{64}$') {
            throw 'Invalid UFD #2 replacement state; inspect ufd2_msft.json'
        }
    } else {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
            -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw 'UFD #2 is missing msft_test_pressanykey.efi or bootx64.efi'
        }
        if (Test-Path -LiteralPath $backup) {
            throw 'An untracked UFD #2 boot-file backup already exists'
        }
        if ((Get-Item -LiteralPath $source).Length -eq 0) {
            throw 'msft_test_pressanykey.efi is empty'
        }
        $state = [pscustomobject]@{
            Serial = 'SVVPUFD2'
            OriginalHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            ReplacementHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        }
        $state | ConvertTo-Json -Compress | Set-Content -LiteralPath "$statePath.tmp" -Encoding Ascii
        Move-Item -LiteralPath "$statePath.tmp" -Destination $statePath -Force
    }

    $hasSource = Test-Path -LiteralPath $source -PathType Leaf
    if ($hasSource -and (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $state.ReplacementHash) {
        throw 'The Microsoft test EFI file changed since the replacement began'
    }
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $state.OriginalHash) {
            throw 'UFD #2 boot-file backup does not match the recorded original'
        }
    } else {
        if (-not $hasSource -or
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $state.OriginalHash) {
            throw 'UFD #2 original boot file or replacement source is missing or changed'
        }
        Move-Item -LiteralPath $destination -Destination $backup
    }

    if ($hasSource) {
        if (Test-Path -LiteralPath $destination) {
            throw 'Unexpected bootx64.efi exists alongside the backup and replacement source'
        }
        Move-Item -LiteralPath $source -Destination $destination
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $state.ReplacementHash) {
        throw 'UFD #2 bootx64.efi does not match msft_test_pressanykey.efi'
    }
    Write-Output "CHANGE_UFD2_COMPLETE: $destination verified; original preserved at $backup"
} catch {
    Write-Output "CHANGE_UFD2_FAILED: $($_.Exception.Message)"
    throw
} finally {
    Stop-Transcript | Out-Null
}
