$ErrorActionPreference = "Stop"

. "$PSScriptRoot\auxiliary.ps1"
. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\extra_software.ps1"

function Enable-NtpServer {
    Write-Output "Enabling NTP Server on Studio VM..."
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer' -Name 'Enabled' -Value 1
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config' -Name 'AnnounceFlags' -Value 5
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -Name 'Type' -Value 'NTP'
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

    Rename-Computer -NewName "$STUDIOCOMPUTERNAME"

    Get-NetAdapter | ForEach-Object {
        $adapterName = $_.Name
        $adapterMac = $_.MacAddress

        $lastMacSegment = $adapterMac.Substring($adapterMac.Length - 2)

        switch ($lastMacSegment) {
            "CC" {
                Write-Output "Setting static IP address to control Network adapter..."
                New-NetIPAddress -InterfaceAlias $adapterName -IPAddress "$STUDIOIP" -PrefixLength 24
                Write-Output "Renaming Control Network adapter..."
                Rename-NetAdapter -Name "$adapterName" -NewName "Control"
                Break
            }
            "DD" {
                Write-Output "Renaming External Network adapter..."
                Rename-NetAdapter -Name "$adapterName" -NewName "External"
                Break
            }
            Default {
                Write-Output "Adapter $adapterName with MAC $adapterMac. Skipped..."
                Break
            }
        }
    }

    Enable-PowerShellRemoting
    Enable-NtpServer

    if ($ENABLERDP) {
        Enable-RemoteDesktop
    }

    Safe-Restart
}

function Stage-Two {
    Set-NewStage -Stage "Three"

    Install-StudioExtraSoftwareBeforeKit

    Safe-Restart
}

function Stage-Three {
    Set-NewStage -Stage "Four"

    Write-Output "Installing $KITTYPE, this might take a while..."
    $kitPath = $null
    $kitArgs = "/q"

    if ($KITTYPE -eq "HLK") {
        $disks = Get-WmiObject -Class Win32_LogicalDisk
        foreach ($disk in ($disks | Where-Object { $_.DriveType -eq 5 })) {
            $kitPathInDisk = Join-Path -Path $disk.DeviceID -ChildPath "HLKSetup.exe"
            if (Test-Path -Path $kitPathInDisk) {
                $kitPath = $kitPathInDisk
                break
            }
        }

        if ($kitPath -eq $null) {
            if (Test-Path -Path "$PSScriptRoot\Kits\HLK${HLKKITVER}\HLKSetup.exe") {
                $kitPath = "$PSScriptRoot\Kits\HLK${HLKKITVER}\HLKSetup.exe"
            } else {
                $kitPath = "$PSScriptRoot\Kits\HLK${HLKKITVER}Setup.exe"
            }
        }
    } else {
        if (Test-Path -Path "$PSScriptRoot\Kits\HCK\Setup.exe") {
            $kitPath = "$PSScriptRoot\Kits\HCK\Setup.exe"
        } else {
            $kitPath = "$PSScriptRoot\Kits\HCKSetup.exe"
        }
    }

    Execute-Command -Path "$kitPath" -Arguments "$kitArgs"
    Write-Output "$KITTYPE Studio setup has finished..."

    if ($REMOVEGUI -eq $TRUE) {
        Remove-WindowsGUI
    }

    Safe-Restart
}

function Stage-Four {
    Set-NewStage -Stage "Five"

    Write-Output "Downloading and updating Filters..."
    if (!(Test-Path -Path "$env:DTMBIN")) {
        Write-Error "Folder $env:DTMBIN does not exist! Please verify that you have the controller installed."
    }

    $filtersFile = "$env:TEMP\FilterUpdates.cab"

    Execute-Command -Path "bitsadmin.exe" -Arguments "/transfer `"Downloading Filters`" `"$FILTERS`" `"$filtersFile`""
    Execute-Command -Path "expand.exe" -Arguments "-i `"$filtersFile`" -f:UpdateFilters.sql `"$env:DTMBIN\`""
    Remove-Item -Path "$filtersFile"
    Push-Location -Path "$env:DTMBIN\"
    Execute-Command -Path "$env:DTMBIN\updatefilters.exe" -Arguments "/s"
    Remove-Item -Path "UpdateFilters.sql"
    Pop-Location

    Get-Service -Name "winrm"
    Write-Output "$env:DTMBIN"

    Safe-Restart
}

function Stage-Five {
    Remove-Stage
    Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "install"

    Install-StudioExtraSoftwareAfterKit

    Safe-Shutdown
}

Start-Stage
