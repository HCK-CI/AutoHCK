$ErrorActionPreference = "Stop"

. "$PSScriptRoot\auxiliary.ps1"
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\extra_software.ps1"

function Configure-TimeSync {
    Write-Output "Configuring Client VM to synchronize time with Studio VM..."
    Start-Service -Name w32time
    Execute-Command -Path "w32tm.exe" -Arguments "/config /manualpeerlist:$STUDIOIP /syncfromflags:manual /reliable:NO /largephaseoffset:0 /update"

    Set-Service -Name w32time -StartupType Automatic
}

function Stage-One {
    Set-NewStage -Stage "Two"

    Allow-InsecureGuestAuth
    Disable-ServerManagerStartupPopup
    Disable-WindowsFirewall
    Set-UnidentifiedNetworksToPrivateLocation
    Disable-WindowsUpdate
    Disable-Screensaver
    Disable-PowerSavingOptions
    Disable-UserAccountControl
    Configure-CrashControl

    Get-NetAdapter | ForEach-Object {
        $adapterName = $_.Name
        $adapterMac = $_.MacAddress

        $macSegments = $adapterMac.Split('-')

        if (($macSegments[5] -eq "CC") -and ($macSegments[4] -eq "CC")) {
            $clientNumber = [int32]("0x" + $macSegments[3])
            $clientIp = $clientNumber + 1
            $clientName = "$CLIENTCOMPUTERNAME$clientNumber"

            Write-Output "Renaming hostname to $clientName"
            Rename-Computer -NewName "$clientName"
            Write-Output "Setting static IP address to MessageDevice Network adapter..."
            New-NetIPAddress -InterfaceAlias "$adapterName" -IPAddress "${CONTROLNET}.${clientIp}" `
                -PrefixLength 24 -DefaultGateway "$STUDIOIP"
            Write-Output "Renaming MessageDevice Network adapter..."
            Rename-NetAdapter -Name "$adapterName" -NewName "MessageDevice"

        } else {
            Write-Output "Adapter $adapterName with MAC $adapterMac. Skipped..."
        }
    }

    "$STUDIOIP $STUDIOCOMPUTERNAME #STUDIO VM IP" |  Out-File -encoding ASCII -append 'C:\Windows\System32\drivers\etc\hosts'

    Enable-PowerShellRemoting

    Safe-Shutdown
}

function Stage-Two {
    Set-NewStage -Stage "Three"

    Configure-TimeSync 

    Write-Output "Setting TestSigning on..."
    Execute-Command -Path "bcdedit.exe" -Arguments "/set testsigning on"

    Install-ClientExtraSoftwareBeforeKit

    Safe-Restart
}

function Stage-Three {
    Set-NewStage -Stage "Four"

    do {
        Write-Output "Waiting for ping to $STUDIOCOMPUTERNAME..."
        # The correct parameter is -ComputerName for PowerShell v5.1. The parameter changed to -TargetName in PowerShell v6.
        # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection?view=powershell-7.1
        # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-connection?view=powershell-5.1
        $pingStatus = Test-Connection -ComputerName "$STUDIOCOMPUTERNAME" -Quiet
    } until ($pingStatus)

    Write-Output "Copying $KITTYPE client installation from studio to client..."

    $clientInstallerFolder = "$env:TEMP\Client"
    Copy-Item -Path "\\$STUDIOCOMPUTERNAME\${KITTYPE}Install\Client" -Destination "$clientInstallerFolder" -Recurse

    Write-Output "Starting $KITTYPE client installation..."
    # HLK Installer
    if (Test-Path -Path "$clientInstallerFolder\setup.cmd") {
        & "$clientInstallerFolder\setup.cmd" "/qb" "ICFAGREE=Yes"
    }
    # HCK Installer
    if (Test-Path -Path "$clientInstallerFolder\setup.exe") {
        & "$clientInstallerFolder\setup.exe" "/qb" "ICFAGREE=Yes"
    }

    Write-Output "$KITTYPE client setup has finished..."

    if ($REMOVEGUI -eq $TRUE) {
        Remove-WindowsGUI
    }

    Get-Service -Name "winrm"
    Safe-Restart
}

function Stage-Four {
    Remove-Stage
    Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "install"

    Install-ClientExtraSoftwareAfterKit

    Safe-Shutdown
}

Start-Stage
