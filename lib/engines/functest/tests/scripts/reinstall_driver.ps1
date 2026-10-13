# Reinstall @driver_module@ from the uploaded driver package.
# On Server 2016 (build 14393), use devcon updateni instead of pnputil -i -a
# because pnputil -i -a fails after a store-only removal on that OS.

$ErrorActionPreference = 'Stop'

$infPath = 'C:\AutoHCK\driver_reinstall\@driver_inf@'
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber

Write-Output "Reinstalling @driver_module@ (OS build $build)"
Write-Output "INF path: $infPath"
Write-Output "INF exists: $(Test-Path $infPath)"

if ($build -le 14393) {
    $devcon = 'C:\devcon\devcon.exe'
    if (-not (Test-Path $devcon)) {
        throw "devcon.exe not found at $devcon — add devcon to extra_software"
    }
    Write-Output "devcon found at $devcon"

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

    $installed = $false
    foreach ($hwid in $hwids) {
        Write-Output "Trying devcon updateni for $hwid ..."
        $ErrorActionPreference = 'Continue'
        $output = & $devcon updateni $infPath "$hwid" 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Write-Output "  devcon output: $output"
        Write-Output "  devcon exit code: $exitCode"
        if ($exitCode -le 1) {
            $installed = $true
            break
        }
        Write-Output "  No match for $hwid, trying next..."
    }

    if (-not $installed) {
        throw "devcon updateni failed for @driver_module@"
    }
} else {
    pnputil -i -a $infPath
    if ($LASTEXITCODE -ne 0) {
        throw "pnputil -i -a failed with exit code $LASTEXITCODE"
    }
}
Write-Output 'PASS: Driver reinstalled'
