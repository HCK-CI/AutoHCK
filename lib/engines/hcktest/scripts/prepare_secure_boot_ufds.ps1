# Runs locally on the SVVP SUT for either combined or separate extraction and
# USB preparation dialogs. Dot-source to load the functions without running them.
param(
    [ValidateSet('ExtractAndPrepare', 'Extract', 'Prepare')]
    [string]$Action = 'ExtractAndPrepare',
    [string]$ZipPath
)

function Get-SecureBootZipIdentity([string] $ZipPath) {
    # Keep the accepted layouts in sync with the watcher's ZIP extraction pattern.
    if ($ZipPath -notmatch '^C:\\HLK\\(?:JobsWorkingDir|Jobs\\WorkingDir)\\Tasks\\([A-Za-z0-9_-]+)\\UefiSecureBootManualTests\.zip$') {
        throw "Unexpected HLK test ZIP path: $ZipPath"
    }
    $taskName = $Matches[1]
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "HLK test ZIP was not found: $ZipPath"
    }
    return [pscustomobject]@{
        TaskName = $taskName
        ZipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash
    }
}

function Get-SecureBootAppsPath([string] $ExtractPath) {
    # Select only x64 UEFI apps, even if other architectures are also present.
    $appCandidates = @(Get-ChildItem -LiteralPath $ExtractPath -Recurse -File -Filter 'pressanykey1.efi' |
        Where-Object {
            $_.Directory.Name -in @('x64', 'amd64') -and
            $_.Directory.Parent.Name -eq 'apps' -and
            $_.Directory.Parent.Parent.Name -eq 'ManualTests'
        })
    if ($appCandidates.Count -ne 1) {
        throw "Expected one x64 ManualTests app directory, found $($appCandidates.Count) under $ExtractPath"
    }
    return $appCandidates[0].Directory.FullName
}

function Get-SecureBootAppHashes([string] $AppsPath) {
    # Preserve the Microsoft test app staging used by the later UFD #2 change.
    $hashes = [ordered]@{}
    foreach ($name in @('pressanykey1.efi', 'pressanykey2.efi', 'msft_test_pressanykey.efi')) {
        $path = Join-Path $AppsPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing $name in $AppsPath"
        }
        $hashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return $hashes
}

function Get-SecureBootContent([string] $Directory, [string] $ZipPath) {
    $statePath = Join-Path $Directory 'extracted_content.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        # Reuse only verified content from this test's extraction, including
        # after a watcher restart. Never silently replace a different task.
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ($state.Version -ne 1 -or $state.ExtractionId -notmatch '^[a-f0-9]{32}$') {
            throw 'Invalid extracted content state'
        }
        if ($ZipPath -and $ZipPath -ne $state.ZipPath) {
            throw 'The popup ZIP path differs from the extracted content state'
        }
        $identity = Get-SecureBootZipIdentity $state.ZipPath
        if ($identity.TaskName -ne $state.TaskName -or $identity.ZipHash -ne $state.ZipHash) {
            throw 'The HLK archive changed after extraction'
        }
        $extractPath = Join-Path $Directory "Extracted\$($identity.TaskName)\$($state.ExtractionId)"
        $appsPath = Get-SecureBootAppsPath $extractPath
        $hashes = Get-SecureBootAppHashes $appsPath
        foreach ($name in $hashes.Keys) {
            if ($hashes[$name] -ne $state.AppHashes.$name) {
                throw "Extracted EFI file changed: $name"
            }
        }
    } else {
        if (-not $ZipPath) {
            throw 'No verified extraction state; complete Unzip the Test Content first'
        }
        $identity = Get-SecureBootZipIdentity $ZipPath
        $extractionId = [guid]::NewGuid().ToString('N')
        # A fresh directory prevents files from an earlier run from filling in
        # missing content in this archive.
        $extractPath = Join-Path $Directory "Extracted\$($identity.TaskName)\$extractionId"
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath
        $appsPath = Get-SecureBootAppsPath $extractPath
        $hashes = Get-SecureBootAppHashes $appsPath
        if ((Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash -ne $identity.ZipHash) {
            throw 'The HLK archive changed during extraction'
        }
        $state = [pscustomobject]@{
            Version = 1
            ZipPath = $ZipPath
            ZipHash = $identity.ZipHash
            TaskName = $identity.TaskName
            ExtractionId = $extractionId
            AppHashes = $hashes
        }
        $state | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath "$statePath.tmp" -Encoding Ascii
        Move-Item -LiteralPath "$statePath.tmp" -Destination $statePath -Force
    }
    return [pscustomobject]@{ ZipPath = $state.ZipPath; AppsPath = $appsPath }
}

function Get-VerifiedUfdDisk([object[]] $AllDisks, [string] $expectedSerial) {
    $matches = @($AllDisks | Where-Object {
        ([string]$_.SerialNumber -replace '\s', '').ToUpperInvariant() -eq $expectedSerial
    })
    if ($matches.Count -ne 1) {
        throw "Expected one disk with serial $expectedSerial; found $($matches.Count)"
    }
    $disk = $matches[0]
    if ([string]$disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or
        $disk.IsOffline -or $disk.IsReadOnly -or $disk.Size -lt 4GB -or $disk.Size -gt 6GB) {
        throw "Disk $($disk.Number) ($expectedSerial) failed USB/size/safety checks"
    }
    if ([string]$disk.PartitionStyle -notin @('RAW', 'MBR', 'GPT')) {
        throw "Disk $($disk.Number) ($expectedSerial) has an unexpected partition style"
    }
    $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
    if ($partitions.Count -gt 1 -or ([string]$disk.PartitionStyle -eq 'RAW' -and $partitions.Count -ne 0)) {
        throw "Disk $($disk.Number) ($expectedSerial) does not have a simple single-volume layout"
    }
    return $disk
}

function Format-VerifiedUfd($disk, [string] $label) {
    $diskNumber = $disk.Number
    if ([string]$disk.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $diskNumber -PartitionStyle MBR | Out-Null
    }

    $partitions = @(Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue)
    if ($partitions.Count -eq 0) {
        $currentDisk = Get-Disk -Number $diskNumber
        if ([string]$currentDisk.PartitionStyle -eq 'MBR') {
            New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter -MbrType FAT32 | Out-Null
        } else {
            New-Partition -DiskNumber $diskNumber -UseMaximumSize -AssignDriveLetter | Out-Null
        }
    }

    $partition = @(Get-Partition -DiskNumber $diskNumber)
    if ($partition.Count -ne 1) {
        throw "Disk $diskNumber no longer has exactly one partition"
    }
    if (-not $partition[0].DriveLetter) {
        Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition[0].PartitionNumber -AssignDriveLetter | Out-Null
        $partition = @(Get-Partition -DiskNumber $diskNumber)
    }
    if (-not $partition[0].DriveLetter) {
        throw "Unable to assign a drive letter to disk $diskNumber"
    }

    Format-Volume -Partition $partition[0] -FileSystem FAT32 -NewFileSystemLabel $label -Confirm:$false -Force | Out-Null
    $volume = Get-Volume -Partition $partition[0]
    if ($volume.FileSystem -ne 'FAT32' -or $volume.FileSystemLabel -ne $label) {
        throw "Disk $diskNumber was not formatted as FAT32 with label $label"
    }
    return ([string]$partition[0].DriveLetter + ':\')
}

function Invoke-SecureBootPreparation {
    param(
        [ValidateSet('ExtractAndPrepare', 'Extract', 'Prepare')]
        [string]$Action,
        [string]$Directory,
        [string]$ZipPath
    )
    $ErrorActionPreference = 'Stop'
    if ($Action -eq 'Prepare' -and $ZipPath) {
        throw 'Prepare must use the saved extraction state, without a ZIP path'
    }
    if ($Action -ne 'Prepare' -and -not $ZipPath) {
        throw "$Action requires a ZIP path"
    }
    $attemptPath = Join-Path $Directory 'prepare_attempted.txt'
    if ($Action -ne 'Extract' -and (Test-Path -LiteralPath $attemptPath)) {
        throw 'UFD preparation was already attempted; inspect the disks and prepare.log before retrying'
    }

    $content = Get-SecureBootContent -Directory $Directory -ZipPath $ZipPath
    if ($Action -eq 'Extract') {
        Write-Output "EXTRACT_TEST_CONTENT_COMPLETE: ZIP=$($content.ZipPath); apps=$($content.AppsPath)"
        return
    }

    # Validate both disk identities and layouts before changing either disk.
    $allDisks = @(Get-Disk)
    $ufd1 = Get-VerifiedUfdDisk $allDisks 'SVVPUFD1'
    $ufd2 = Get-VerifiedUfdDisk $allDisks 'SVVPUFD2'
    if ($ufd1.Number -eq $ufd2.Number) {
        throw 'UFD #1 and UFD #2 resolved to the same Windows disk'
    }

    # Reserve the destructive attempt exclusively, before any disk changes.
    # A restart (or a second watcher) must not repeat a partial format.
    $attemptFile = [IO.File]::Open(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($attemptPath),
        [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($content.ZipPath)
        $attemptFile.Write($bytes, 0, $bytes.Length)
        $attemptFile.Flush($true)
    } finally {
        $attemptFile.Dispose()
    }

    $ufd1Root = Format-VerifiedUfd $ufd1 'UFD #1'
    $ufd2Root = Format-VerifiedUfd $ufd2 'UFD #2'
    $ufd1Boot = Join-Path $ufd1Root 'EFI\BOOT'
    $ufd2Boot = Join-Path $ufd2Root 'EFI\BOOT'
    New-Item -ItemType Directory -Path $ufd1Boot, $ufd2Boot -Force | Out-Null

    $copies = @(
        @{ Source = (Join-Path $content.AppsPath 'pressanykey1.efi'); Destination = (Join-Path $ufd1Boot 'bootx64.efi') },
        @{ Source = (Join-Path $content.AppsPath 'pressanykey2.efi'); Destination = (Join-Path $ufd2Boot 'bootx64.efi') },
        @{ Source = (Join-Path $content.AppsPath 'msft_test_pressanykey.efi'); Destination = (Join-Path $ufd2Boot 'msft_test_pressanykey.efi') }
    )
    foreach ($copy in $copies) {
        Copy-Item -LiteralPath $copy.Source -Destination $copy.Destination -Force
        if ((Get-FileHash -LiteralPath $copy.Source).Hash -ne (Get-FileHash -LiteralPath $copy.Destination).Hash) {
            throw "Copied EFI file did not match source: $($copy.Destination)"
        }
    }
    Write-Output "PREPARE_UFDS_COMPLETE: SVVPUFD1=$ufd1Root; SVVPUFD2=$ufd2Root; ZIP=$($content.ZipPath)"
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $directory = 'C:\AutoHCK\SecureBootManual'
    Start-Transcript -Path (Join-Path $directory 'prepare.log') -Append | Out-Null
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Test content preparation requires an elevated interactive watcher'
        }
        Invoke-SecureBootPreparation -Action $Action -Directory $directory -ZipPath $ZipPath
    } finally {
        Stop-Transcript | Out-Null
    }
}
