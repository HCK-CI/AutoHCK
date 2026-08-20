# Remove @driver_module@ from the Windows DriverStore using pnputil.
# On Server 2016 (build 14393), also use devcon to remove the device
# because pnputil on that OS does not support /uninstall.

$ErrorActionPreference = 'Stop'

$drv = Get-WindowsDriver -Online |
    Where-Object { $_.OriginalFileName -like '*@driver_module@.inf' } |
    Select-Object -First 1

if (-not $drv) {
    throw 'Driver @driver_module@ not found in DriverStore'
}

$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber

Write-Output "Removing $($drv.Driver) (OS build $build)"

if ($build -le 14393) {
    pnputil /f /d $drv.Driver
    if ($LASTEXITCODE -ne 0) {
        throw "pnputil /f /d failed with exit code $LASTEXITCODE"
    }

    $devcon = 'C:\devcon\devcon.exe'
    if (-not (Test-Path $devcon)) {
        throw "devcon.exe not found at $devcon — add devcon to extra_software"
    }

    # Virtio PCI hardware IDs (transitional and modern), matching tp-qemu
    $hwidMap = @{
        'viostor'   = @('PCI\VEN_1AF4&DEV_1001', 'PCI\VEN_1AF4&DEV_1042')
        'vioscsi'   = @('PCI\VEN_1AF4&DEV_1004', 'PCI\VEN_1AF4&DEV_1048')
        'netkvm'    = @('PCI\VEN_1AF4&DEV_1000', 'PCI\VEN_1AF4&DEV_1041')
        'balloon'   = @('PCI\VEN_1AF4&DEV_1002', 'PCI\VEN_1AF4&DEV_1045')
        'vioserial' = @('PCI\VEN_1AF4&DEV_1003', 'PCI\VEN_1AF4&DEV_1043')
        'viorng'    = @('PCI\VEN_1AF4&DEV_1005', 'PCI\VEN_1AF4&DEV_1044')
        'viofs'     = @('PCI\VEN_1AF4&DEV_105A')
        'viogpu'    = @('PCI\VEN_1AF4&DEV_1050')
        'vioinput'  = @('PCI\VEN_1AF4&DEV_1052')
        'viosock'   = @('PCI\VEN_1AF4&DEV_1053', 'PCI\VEN_1AF4&DEV_1012')
        'pvpanic'   = @('ACPI\QEMU0001')
        'fwcfg'     = @('ACPI\QEMU0002', 'ACPI\VEN_QEMU&DEV_0002')
    }

    $hwids = $hwidMap['@driver_module@']
    if (-not $hwids) {
        throw "No HWID mapping for @driver_module@"
    }

    foreach ($hwid in $hwids) {
        $found = & $devcon find "$hwid*" 2>&1
        if ($found -match 'matching device') {
            Write-Output "Removing device $hwid"
            $ErrorActionPreference = 'Continue'
            & $devcon remove "$hwid*"
            $removeExit = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            # devcon remove: 0 = success, 1 = reboot needed; anything else is an error
            if ($removeExit -gt 1) {
                throw "devcon remove failed for $hwid (exit $removeExit)"
            }
        }
    }
} else {
    pnputil /delete-driver $drv.Driver /uninstall /force
    if ($LASTEXITCODE -ne 0) {
        throw "pnputil failed with exit code $LASTEXITCODE"
    }
}
Write-Output 'PASS: Driver removed from store'
