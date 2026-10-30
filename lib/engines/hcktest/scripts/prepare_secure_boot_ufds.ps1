# Runs locally on the SVVP SUT when the AutoIt watcher recognizes the current
# HLK "Prepare USB Flash Drives" popup. The watcher passes its ZIP path.
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ZipPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Start-Transcript -Path 'C:\AutoHCK\SecureBootManual\prepare.log' -Append | Out-Null

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'UFD preparation requires an elevated interactive watcher'
}

# Keep the accepted layouts in sync with the watcher's ZIP extraction pattern.
if ($ZipPath -notmatch '^C:\\HLK\\(?:JobsWorkingDir|Jobs\\WorkingDir)\\Tasks\\[A-Za-z0-9_-]+\\UefiSecureBootManualTests\.zip$') {
    throw "Unexpected HLK test ZIP path: $ZipPath"
}
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    throw "HLK test ZIP was not found: $ZipPath"
}

$taskName = Split-Path -Leaf (Split-Path -Parent $ZipPath)
$extractPath = Join-Path 'C:\AutoHCK\SecureBootManual\Extracted' $taskName
Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractPath -Force

# Select only the x64 UEFI application directory, even if the ZIP also
# contains binaries for other firmware architectures.
$appCandidates = @(Get-ChildItem -LiteralPath $extractPath -Recurse -File -Filter 'pressanykey1.efi' |
    Where-Object {
        $_.Directory.Name -in @('x64', 'amd64') -and
        $_.Directory.Parent.Name -eq 'apps' -and
        $_.Directory.Parent.Parent.Name -eq 'ManualTests'
    })
if ($appCandidates.Count -ne 1) {
    throw "Expected one x64 ManualTests app directory, found $($appCandidates.Count) under $extractPath"
}
$appsPath = $appCandidates[0].Directory.FullName
$sourceNames = @('pressanykey1.efi', 'pressanykey2.efi', 'msft_test_pressanykey.efi')
foreach ($name in $sourceNames) {
    if (-not (Test-Path -LiteralPath (Join-Path $appsPath $name) -PathType Leaf)) {
        throw "Missing $name in $appsPath"
    }
}

# Validate both disk identities and layouts before changing either disk.
$allDisks = @(Get-Disk)
function Get-VerifiedUfdDisk([string] $expectedSerial) {
    $matches = @($allDisks | Where-Object {
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

$ufd1 = Get-VerifiedUfdDisk 'SVVPUFD1'
$ufd2 = Get-VerifiedUfdDisk 'SVVPUFD2'
if ($ufd1.Number -eq $ufd2.Number) {
    throw 'UFD #1 and UFD #2 resolved to the same Windows disk'
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

$ufd1Root = Format-VerifiedUfd $ufd1 'UFD #1'
$ufd2Root = Format-VerifiedUfd $ufd2 'UFD #2'
$ufd1Boot = Join-Path $ufd1Root 'EFI\BOOT'
$ufd2Boot = Join-Path $ufd2Root 'EFI\BOOT'
New-Item -ItemType Directory -Path $ufd1Boot, $ufd2Boot -Force | Out-Null

$copies = @(
    @{ Source = (Join-Path $appsPath 'pressanykey1.efi'); Destination = (Join-Path $ufd1Boot 'bootx64.efi') },
    @{ Source = (Join-Path $appsPath 'pressanykey2.efi'); Destination = (Join-Path $ufd2Boot 'bootx64.efi') },
    @{ Source = (Join-Path $appsPath 'msft_test_pressanykey.efi'); Destination = (Join-Path $ufd2Boot 'msft_test_pressanykey.efi') }
)
foreach ($copy in $copies) {
    Copy-Item -LiteralPath $copy.Source -Destination $copy.Destination -Force
    if ((Get-FileHash -LiteralPath $copy.Source).Hash -ne (Get-FileHash -LiteralPath $copy.Destination).Hash) {
        throw "Copied EFI file did not match source: $($copy.Destination)"
    }
}

Write-Output "PREPARE_UFDS_COMPLETE: SVVPUFD1=$ufd1Root; SVVPUFD2=$ufd2Root; ZIP=$ZipPath"
Stop-Transcript | Out-Null
