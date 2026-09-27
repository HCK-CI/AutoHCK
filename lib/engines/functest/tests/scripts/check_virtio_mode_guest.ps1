# tp-qemu virtio_mode.py: verify_virtio_mode_guest_win (all virtio_mode drivers)
# modern:       PCI device id >= 0x1040
# legacy/trans:  id < 0x1040 — MEM BAR rules (devcon path matches tp-qemu; WMI when no devcon)
$ErrorActionPreference = 'Stop'

$expected = '@virtio_mode@'.Trim().ToLowerInvariant()
if ($expected -notin @('modern', 'legacy', 'transitional')) {
    throw "virtio_mode must be modern, legacy, or transitional; got '$expected' (set --virtio-mode on CLI)"
}

$profileKey = '@driver_module@'.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($profileKey) -or $profileKey -match '^@') {
    throw "driver_module was not substituted by functest; got '$profileKey'"
}
if ($profileKey -eq 'vioser') { $profileKey = 'vioserial' }

$Profiles = @{
    viorng    = @{ Label = 'VirtIO RNG';     Service = 'VirtRng';      HwIdPattern = 'VEN_1AF4&DEV_(1005|1044)' }
    netkvm    = @{ Label = 'VirtIO Ethernet'; Service = 'netkvm';     HwIdPattern = 'VEN_1AF4&DEV_(1000|1041)' }
    viostor   = @{ Label = 'VirtIO Block';   Service = 'viostor';      HwIdPattern = 'VEN_1AF4&DEV_(1001|1042)' }
    vioscsi   = @{ Label = 'VirtIO SCSI';    Service = 'vioscsi';      HwIdPattern = 'VEN_1AF4&DEV_(1004|1048)' }
    vioserial = @{ Label = 'VirtIO Serial';  Service = 'VirtioSerial'; HwIdPattern = 'VEN_1AF4&DEV_(1003|1043)' }
    balloon   = @{ Label = 'VirtIO Balloon'; Service = 'BALLOON';      HwIdPattern = 'VEN_1AF4&DEV_(1002|1045)' }
}

if (-not $Profiles.ContainsKey($profileKey)) {
    throw "Unknown virtio profile '$profileKey'. Known: $(($Profiles.Keys | Sort-Object) -join ', ')"
}

$p = $Profiles[$profileKey]
Write-Output "virtio_device_profile=$profileKey label=$($p.Label)"

$LEGACY_BAR_SPAN_DEVCON = 0xFFF
# WMI reports 4 KiB MMIO as span 0x1000; legacy virtio often has no MEM at all (tp-qemu: no devcon MEM => legacy).
$LEGACY_BAR_SPANS_WMI = [int64[]]@(0xFFF, 0x1000)
# WMI often reports multi-megabyte "memory" on PCI nodes (not devcon MEM BARs). Ignore for virtio_mode.
$WMI_BAR_SPAN_MAX = [int64]0xFFFFF
$MODERN_PCI_DEVICE_ID = 0x1040

function ConvertTo-WqlDeviceId {
    param([string]$DeviceId)
    return $DeviceId.Replace('\', '\\').Replace("'", "''")
}

function Find-DevconExe {
    $roots = @()
    $tb = '@test_binaries_dir@'.Trim()
    if (-not [string]::IsNullOrWhiteSpace($tb) -and $tb -notmatch '^@') {
        $roots += $tb
    }
    $roots += @('C:\AutoHCK')

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hit = Get-ChildItem -LiteralPath $root -Recurse -Filter 'devcon.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Invoke-DevconMemorySpans {
    param(
        [string]$HardwareId,
        [string]$DevconExe
    )

    $spans = [System.Collections.Generic.List[int64]]::new()
    $exitCode = 1

    if (-not $DevconExe) {
        return @{ Spans = @(); ExitCode = $exitCode }
    }

    $arg = "@$HardwareId"
    $raw = & $DevconExe resources $arg 2>&1
    if ($null -ne $LASTEXITCODE) {
        $exitCode = [int]$LASTEXITCODE
    } else {
        $exitCode = 0
    }

    $text = ($raw | Out-String)
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -notmatch 'MEM|Memory') { continue }
        if ($line -notmatch '([0-9A-Fa-f]+)\s*-\s*([0-9A-Fa-f]+)') { continue }
        $start = [Convert]::ToInt64($Matches[1], 16)
        $end = [Convert]::ToInt64($Matches[2], 16)
        $spans.Add($end - $start)
    }

    return @{ Spans = @($spans.ToArray()); ExitCode = $exitCode }
}

function Get-WmiMemorySpansForDevice {
    param([string]$InstanceId)

    $spans = [System.Collections.Generic.List[int64]]::new()

    $pnpEntity = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -eq $InstanceId } |
        Select-Object -First 1

    if ($pnpEntity) {
        $memRows = @(Get-CimAssociatedInstance -InputObject $pnpEntity -ResultClassName Win32_DeviceMemoryAddress -ErrorAction SilentlyContinue)
        foreach ($row in $memRows) {
            if ($null -eq $row.StartingAddress -or $null -eq $row.EndingAddress) { continue }
            $spans.Add([int64]$row.EndingAddress - [int64]$row.StartingAddress)
        }
    }

    if ($spans.Count -eq 0) {
        $wqlId = ConvertTo-WqlDeviceId $InstanceId
        $query = "ASSOCIATORS OF {Win32_PnPEntity.DeviceID='$wqlId'} WHERE ResultClass=Win32_DeviceMemoryAddress"
        $memRows = @(Get-CimInstance -Query $query -ErrorAction SilentlyContinue)
        foreach ($row in $memRows) {
            if ($null -eq $row.StartingAddress -or $null -eq $row.EndingAddress) { continue }
            $spans.Add([int64]$row.EndingAddress - [int64]$row.StartingAddress)
        }
    }

    return ,@($spans.ToArray())
}

function Normalize-BarSpans {
    param(
        [int64[]]$Spans,
        [ValidateSet('devcon', 'wmi')]
        [string]$Source
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $usable = [System.Collections.Generic.List[int64]]::new()
    $seen = @{}

    foreach ($span in $Spans) {
        $key = "{0:X}" -f $span
        if ($seen[$key]) { continue }
        $seen[$key] = $true

        if ($Source -eq 'wmi' -and $span -gt $WMI_BAR_SPAN_MAX) {
            $lines.Add(("MEM span=0x{0:X} (ignored: WMI range > 0x{1:X}, not a virtio BAR)" -f $span, $WMI_BAR_SPAN_MAX))
            continue
        }

        $lines.Add(("MEM span=0x{0:X}" -f $span))
        $usable.Add($span)
    }

    return @{ Spans = @($usable.ToArray()); Lines = $lines.ToArray() }
}

function Resolve-GuestModeFromSpans {
    param(
        [int64[]]$Spans,
        [ValidateSet('devcon', 'wmi')]
        [string]$Source
    )

    $mode = 'legacy'
    $lines = [System.Collections.Generic.List[string]]::new()

    if ($Spans.Count -eq 0) {
        $lines.Add('MEM: no usable MMIO BAR spans (legacy virtio often has IO only — tp-qemu => legacy)')
        return @{ Mode = $mode; Lines = $lines.ToArray() }
    }

    foreach ($span in $Spans) {
        if ($Source -eq 'devcon') {
            # virtio_mode.py: (end - start) != 0xFFF => transitional
            if (($span - $LEGACY_BAR_SPAN_DEVCON) -ne 0) {
                $mode = 'transitional'
            }
        } else {
            # WMI: 4 KiB is 0xFFF or 0x1000; modern BAR is strictly larger than 4 KiB
            if ($LEGACY_BAR_SPANS_WMI -notcontains $span) {
                $mode = 'transitional'
            }
        }
    }
    return @{ Mode = $mode; Lines = $lines.ToArray() }
}

function Build-MemModeResult {
    param(
        [int64[]]$Spans,
        [ValidateSet('devcon', 'wmi')]
        [string]$Source
    )

    $norm = Normalize-BarSpans -Spans $Spans -Source $Source
    $resolved = Resolve-GuestModeFromSpans -Spans $norm.Spans -Source $Source
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("MEM source=$Source")
    foreach ($l in $norm.Lines) { $out.Add($l) }
    foreach ($l in $resolved.Lines) { $out.Add($l) }
    return @{ Mode = $resolved.Mode; Lines = $out.ToArray() }
}

function Get-VirtioGuestMode {
    param(
        [int]$DeviceId,
        [string]$InstanceId,
        [string]$HardwareId,
        [string]$DevconExe
    )

    if ($DeviceId -ge $MODERN_PCI_DEVICE_ID) {
        return @{ Mode = 'modern'; Lines = @() }
    }

    # Prefer DevCon when available; if it returns no MEM spans (common on Win2025+), fall back to WMI.
    if ($DevconExe) {
        $dc = Invoke-DevconMemorySpans -HardwareId $HardwareId -DevconExe $DevconExe
        Write-Output ("devcon exit={0}" -f $dc.ExitCode)
        if (@($dc.Spans).Count -gt 0) {
            return Build-MemModeResult -Spans $dc.Spans -Source 'devcon'
        }
        Write-Output 'devcon returned no usable MEM spans; falling back to WMI'
    }

    $wmiSpans = Get-WmiMemorySpansForDevice -InstanceId $InstanceId
    return Build-MemModeResult -Spans $wmiSpans -Source 'wmi'
}

$dev = Get-PnpDevice | Where-Object { $_.Service -eq $p.Service } | Select-Object -First 1
if (-not $dev) {
    $dev = Get-PnpDevice | Where-Object {
        $hw = ($_.HardwareID | ForEach-Object { $_ }) -join '|'
        $hw -match $p.HwIdPattern
    } | Select-Object -First 1
}

if (-not $dev) {
    throw "$($p.Label) PnP device not found (profile=$profileKey)"
}
if ($dev.Status -ne 'OK') {
    throw "$($p.Label) not OK: $($dev.Status)"
}

$hwid = @($dev.HardwareID) | Where-Object { $_ -match 'DEV_([0-9A-Fa-f]{4})' } | Select-Object -First 1
if ($hwid -notmatch 'DEV_([0-9A-Fa-f]{4})') {
    throw 'Bad HWID: no DEV_xxxx in HardwareID'
}
$deviceId = [Convert]::ToInt32($Matches[1], 16)
Write-Output ("HardwareID={0} device_id=0x{1:X4}" -f $hwid, $deviceId)
Write-Output ("PnP InstanceId={0}" -f $dev.InstanceId)

$devconExe = Find-DevconExe
if ($devconExe) {
    Write-Output "devcon=$devconExe"
}

$modeResult = Get-VirtioGuestMode -DeviceId $deviceId -InstanceId $dev.InstanceId -HardwareId $hwid -DevconExe $devconExe
foreach ($line in $modeResult.Lines) {
    Write-Output $line
}
$guestMode = [string]$modeResult.Mode

Write-Output "expected virtio_mode=$expected guest_mode=$guestMode"
if ($guestMode -ne $expected) {
    throw "virtio mode mismatch: expected $expected, guest $guestMode"
}
Write-Output "PASS: virtio mode in guest is $guestMode (profile=$profileKey)"

