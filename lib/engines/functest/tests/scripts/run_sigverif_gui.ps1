<#
.SYNOPSIS
    Run Windows File Signature Verification (sigverif) via AutoIt and confirm
    @driver_module@.sys is Signed — mirrors KAR/avocado win_sigverif.

.DESCRIPTION
    Requires suite or case extra_software: ["autoit"]. The test case uploads common
    helpers, sigverif.au3, and sigverif_worker.ps1 via files_action.

    This launcher only hops to the interactive desktop via
    Invoke-InteractiveSession.ps1; GUI work lives in the worker.
#>

$ErrorActionPreference = 'Stop'

$moduleName = '@driver_module@'
if (-not $moduleName -or $moduleName -like '@*@') {
    Write-Output 'FAIL: driver_module was not substituted by functest'
    exit 1
}

$workDir = 'C:\AutoHCK\sigverif_work'
$resultFile = Join-Path $workDir 'result.txt'
$workerLog = Join-Path $workDir 'worker.log'
$workerScript = 'C:\AutoHCK\sigverif_worker.ps1'
$interactiveHelper = 'C:\AutoHCK\common\Invoke-InteractiveSession.ps1'
$scanTimeoutSec = 900

Write-Output "driver_module=$moduleName"

if (-not (Test-Path $interactiveHelper)) {
    Write-Output "FAIL: interactive helper not found at $interactiveHelper (files_action upload required)"
    exit 1
}

# Uploaded helpers need an explicit Bypass launch from Session 0 guest_run_file.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $interactiveHelper `
    -ScriptPath $workerScript `
    -ArgumentList "-ModuleName `"$moduleName`"" `
    -TaskName 'AutoHCK_Sigverif' `
    -ResultFile $resultFile `
    -TimeoutSec ($scanTimeoutSec + 60) `
    -WorkDir $workDir `
    -WorkerLog $workerLog
exit $LASTEXITCODE
