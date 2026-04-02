$FILTERS = "https://go.microsoft.com/fwlink/?linkid=875139"
$STUDIOCOMPUTERNAME = "STUDIO"
$CLIENTCOMPUTERNAME = "CL"
$CONTROLNET = "192.168.100" # The =FIRST THREE= octets of the IP
$STUDIOIP = "${CONTROLNET}.1"
$KITTYPE = "HLK"
$HLKKITVER = 1809
$REMOVEGUI = $false
$DEBUG = $false
$ENABLERDP = $true
$STAGEFILE = "$env:ProgramData\HLK-setup-stage.txt"
$ARGSPATH = "$PSScriptRoot\args.ps1"
$EXTRASOFTWAREDIRECTORY = "$PSScriptRoot\extra-software"

if (Test-Path -Path "$ARGSPATH") {
    . "$ARGSPATH"
}

function Execute-Command ($Path, $Arguments) {
    Write-Output "Execution $Path $Arguments"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "$Path"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = "$Arguments"
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo

    $OutEvent = Register-ObjectEvent -Action {
        Write-Output $Event.SourceEventArgs.Data
    } -InputObject $p -EventName "OutputDataReceived"
    $ErrEvent = Register-ObjectEvent -Action {
        Write-Output $Event.SourceEventArgs.Data
    } -InputObject $p -EventName "ErrorDataReceived"

    $p.Start()
    $p.BeginOutputReadLine()
    $p.BeginErrorReadLine()

    # Do not think about calling WaitForExit on the process,
    # because then no output is generated until the process
    # has finished
    do
    {
        Write-Output 'Waiting for process to finish...'
        Start-Sleep -Seconds 1
    }
    while (!$p.HasExited)

    if ($p.ExitCode -ne 0) {
       Write-Error "Process exited with code $($p.ExitCode)"
    } else {
       Write-Output "Process exited successfully"
    }

    $OutEvent.Name, $ErrEvent.Name |
    ForEach-Object {Unregister-Event -SourceIdentifier $_}

    Write-Output "Execution finished"
}

function Set-NewStage() {
    param (
        $Stage
    )
    Write-Output "Set new stage to file: $Stage"
    Set-Content -Path "$STAGEFILE" -Value "$Stage"
}

function Get-CurrentStage() {
    if ((Test-Path $STAGEFILE)) {
        Get-Content -Path "$STAGEFILE"
    } else {
        Write-Output "One"
    }
}

function Remove-Stage() {
    Write-Output "Remove stage file: $STAGEFILE"
    Remove-Item -Path "$STAGEFILE"
}

function Start-Stage() {
    $stage = Get-CurrentStage
    $time = Get-Date -UFormat "%d-%m-%Y-%H-%M-%S"

    Start-Transcript -Path "$env:TEMP\install-$stage-$time.log" -Force
    Write-Output "[$time] Starting stage $stage..."
    Invoke-Expression "Stage-$stage"
}

function Safe-Restart() {
    Stop-Transcript

    if ($DEBUG -eq $true) {
        Read-Host 'Press any key to continue...'
    }

    Restart-Computer
}

function Safe-Shutdown() {
    Stop-Transcript

    if ($DEBUG -eq $true) {
        Read-Host 'Press any key to continue...'
    }

    Stop-Computer
}

function Set-Registry {
    param (
        $Path,
        $Name,
        $Value,
        $Type
    )

    if (Test-Path "$Path") {
        New-ItemProperty -Path "$Path" -Name "$Name" -Value "$Value" `
            -PropertyType "$Type" -Force
     } else {
        New-Item -Path "$Path" -Force
        New-ItemProperty -Path "$Path" -Name "$Name" -Value "$Value" `
            -PropertyType "$Type" -Force
     }
}
