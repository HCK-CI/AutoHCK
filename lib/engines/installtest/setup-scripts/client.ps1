$ErrorActionPreference = "Stop"

. "$PSScriptRoot\auxiliary.ps1"
. "$PSScriptRoot\common.ps1"

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
        $clientName = $VMNAMES[$clientNumber]
        if (-not $clientName) {
            Write-Error "No VM name found in VMNAMES for client number $clientNumber"
        }

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

Enable-PowerShellRemoting

Write-Output "Setting TestSigning on..."
Execute-Command -Path "bcdedit.exe" -Arguments "/set testsigning on"

Write-Output "Removing Run key to prevent re-execution on next boot..."
Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "install" -ErrorAction SilentlyContinue

Stop-Computer -Force
