
. "$PSScriptRoot\auxiliary.ps1"

function Allow-InsecureGuestAuth {
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Type DWord -Value 1
}

function Disable-ServerManagerStartupPopup {
    Write-Output "Disabling Server Manager popup on startup..."
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" `
        -Type DWord -Value 1
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Oobe" -Name "DoNotOpenInitialConfigurationTasksAtLogon" `
        -Type DWord -Value 1
}

function Disable-WindowsFirewall {
    Write-Output "Disabling Windows Firewall..."
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Security Center" -Name "FirewallDisableNotify" -Type DWord -Value 1
}

function Set-UnidentifiedNetworksToPrivateLocation {
    Write-Output "Setting unidentified networks to Private Location..."
    Set-Registry -Name "Category" -Type DWord -Value "1" `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24"
}

function Disable-WindowsUpdate {
    Write-Output "Disabling Windows Update..."
    Set-Service -Name "wuauserv" -StartupType Disabled
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" `
        -Name "AUOptions" -Type DWord -Value 1
}

function Disable-Screensaver {
    Write-Output "Disabling screensaver..."
    Set-Registry -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Type String -Value "0"
    Set-Registry -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Type String -Value ""
}

function Disable-PowerSavingOptions {
    Write-Output "Disabling power saving options..."
    Execute-Command -Path "powercfg.exe" -Arguments "-change -monitor-timeout-ac 0"
    Execute-Command -Path "powercfg.exe" -Arguments "-change -disk-timeout-ac 0"
    Execute-Command -Path "powercfg.exe" -Arguments "-change -standby-timeout-ac 0"
    Execute-Command -Path "powercfg.exe" -Arguments "-hibernate off"
}

function Enable-PowerShellRemoting {
    Write-Output "Enabling powershell remoting..."
    Start-Sleep -Seconds 30
    Set-NetConnectionProfile -NetworkCategory Private
    Execute-Command -Path 'C:\Windows\System32\winrm.cmd' -Arguments 'quickconfig -q'
    Execute-Command -Path 'C:\Windows\System32\winrm.cmd' -Arguments 'set winrm/config "@{MaxTimeoutms="14400000"}"'
    Execute-Command -Path 'C:\Windows\System32\winrm.cmd' -Arguments 'set winrm/config/service/auth "@{Basic="true"}"'
    Execute-Command -Path 'C:\Windows\System32\winrm.cmd' -Arguments 'set winrm/config/service "@{AllowUnencrypted="true"}"'
}

function Enable-RemoteDesktop {
    Write-Output "Enabling Remote Desktop..."
    # Enable Remote Desktop connections.
    Set-Registry -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Type DWord -Value 0

    # Disable Network Level Authentication (NLA) for compatibility with clients like 'rdesktop'.
    # WARNING: This is less secure and exposes the server to pre-authentication attacks.
    Set-Registry -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Type DWord -Value 0

    # Enable multiple sessions for single user
    Set-Registry -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fSingleSessionPerUser" -Type DWord -Value 0

    # Ensure Remote Desktop service is running
    Set-Service -Name "TermService" -StartupType Automatic
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue

    Write-Output "Remote Desktop has been enabled"
}

function Disable-UserAccountControl {
    Write-Output "Disabling User Account Control (UAC)..."

    # Disable UAC by setting EnableLUA to 0
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Type DWord -Value 0

    # Set FilterAdministratorToken to 0 to disable UAC for built-in administrator
    Set-Registry -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "FilterAdministratorToken" -Type DWord -Value 0

    Write-Output "UAC has been disabled. A restart is required for changes to take effect."
}

function Configure-CrashControl {
    Write-Output "Configuring crash control settings..."

    # Enable NMI crash dump (allows triggering crash dumps via NMI)
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" `
        -Name "NMICrashDump" -Type DWord -Value 1

    # Set crash dump to kernel memory dump (value 2)
    Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" `
        -Name "CrashDumpEnabled" -Type DWord -Value 2

    # Configure AutoReboot setting based on no_reboot_after_bugcheck parameter
    if ($NOREBOOTAFTERBUGCHECK -eq $TRUE) {
        Write-Output "Disabling automatic reboot after crash (keeps the system in crashed state for debugging)"
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" `
            -Name "AutoReboot" -Type DWord -Value 0
    } else {
        Write-Output "Enabling automatic reboot after crash (default behavior)"
        Set-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" `
            -Name "AutoReboot" -Type DWord -Value 1
    }

    Write-Output "Crash control settings have been configured."
}

function Remove-WindowsGUI {
    Write-Output "Removing windows GUI..."
    Remove-WindowsFeature Server-Gui-Shell, Server-Gui-Mgmt-Infra
}
