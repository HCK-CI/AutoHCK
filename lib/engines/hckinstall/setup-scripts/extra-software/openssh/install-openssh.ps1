# Installs and configures the OpenSSH Server on any supported guest.
#
# Delivered as an extra-software package so the same code path covers every
# platform (Win10 x86/x64, Win11, Server 2016-2025, ARM64 in future), online or
# air-gapped. The tier ladder tries the inbox mechanisms first and always falls
# back to the bundled Win32-OpenSSH portable zip, which is the only source that
# works on Server 2016 (no inbox OpenSSH) and fully offline.
#
# This script runs as its own powershell.exe process (see the package configs),
# so it is intentionally self-contained and does not rely on common.ps1 helpers.

param (
    # Folder this package was deployed to on the guest (@sw_path@).
    [String]$PackagePath = $PSScriptRoot,
    # Arch-matched Win32-OpenSSH zip file name (@file_name@), e.g. OpenSSH-Win64.zip.
    [String]$ZipName
)

$ErrorActionPreference = "Stop"

$CapabilityName = "OpenSSH.Server~~~~0.0.1.0"
$InstallDir = Join-Path $env:ProgramFiles "OpenSSH"
$SshdExe = Join-Path $env:SystemRoot "System32\OpenSSH\sshd.exe"

function Get-SshdExePath {
    # Inbox OpenSSH lands in System32\OpenSSH; the portable zip lands in
    # %ProgramFiles%\OpenSSH. Return whichever exists.
    foreach ($candidate in @($SshdExe, (Join-Path $InstallDir "sshd.exe"))) {
        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-SshdPresent {
    $service = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    return ($null -ne $service) -and ($null -ne (Get-SshdExePath))
}

function Install-FromWindowsFeature {
    if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) {
        return $false
    }

    $feature = Get-WindowsFeature -Name "OpenSSH-Server" -ErrorAction SilentlyContinue
    if ($null -eq $feature) {
        return $false
    }
    if ($feature.Installed) {
        return $true
    }

    Install-WindowsFeature -Name "OpenSSH-Server" -ErrorAction Stop | Out-Null
    return $true
}

function Install-FromWindowsCapability {
    $capability = Get-WindowsCapability -Online -Name $CapabilityName -ErrorAction SilentlyContinue
    if (($null -ne $capability) -and ($capability.State -eq "Installed")) {
        return $true
    }

    # Needs Windows Update reachability; fails offline (0x8024402c). The caller
    # falls back to the portable zip in that case.
    $result = Add-WindowsCapability -Online -Name $CapabilityName -ErrorAction Stop
    $capability = Get-WindowsCapability -Online -Name $CapabilityName -ErrorAction SilentlyContinue
    return ($null -ne $capability) -and ($capability.State -eq "Installed")
}

function Install-FromPortableZip {
    if ([String]::IsNullOrEmpty($ZipName)) {
        throw "No portable OpenSSH zip name was provided (ZipName is empty)"
    }

    $zipPath = Join-Path $PackagePath $ZipName
    if (-not (Test-Path -Path $zipPath)) {
        throw "Portable OpenSSH zip not found: $zipPath"
    }

    Write-Output "Installing OpenSSH Server from portable zip: $zipPath"

    # The zip contains a top-level OpenSSH-* folder; flatten it into $InstallDir.
    $extractTmp = Join-Path $env:TEMP "openssh-portable-$PID"
    if (Test-Path -Path $extractTmp) {
        Remove-Item -Path $extractTmp -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

    $payload = Get-ChildItem -Path $extractTmp -Directory |
        Where-Object { Test-Path -Path (Join-Path $_.FullName "sshd.exe") } |
        Select-Object -First 1
    if ($null -eq $payload) {
        # Some zips extract the binaries directly without a wrapper folder.
        if (Test-Path -Path (Join-Path $extractTmp "sshd.exe")) {
            $payload = Get-Item -Path $extractTmp
        } else {
            throw "sshd.exe not found inside $zipPath"
        }
    }

    if (Test-Path -Path $InstallDir) {
        # Stop a previous install's service before overwriting its binaries.
        Stop-Service -Name "sshd" -ErrorAction SilentlyContinue
        Remove-Item -Path $InstallDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $payload.FullName "*") -Destination $InstallDir -Recurse -Force
    Remove-Item -Path $extractTmp -Recurse -Force

    $installSshd = Join-Path $InstallDir "install-sshd.ps1"
    if (-not (Test-Path -Path $installSshd)) {
        throw "install-sshd.ps1 missing in $InstallDir"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installSshd

    # Make the portable binaries discoverable on PATH for interactive use.
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$InstallDir", "Machine")
    }
}

function Install-OpenSSHServer {
    if (Test-SshdPresent) {
        Write-Output "OpenSSH Server already present; skipping install"
        return
    }

    # Tier 1: Windows Server feature (uses local payload when available).
    try {
        if (Install-FromWindowsFeature) {
            Write-Output "Installed OpenSSH Server via Install-WindowsFeature"
            if (Test-SshdPresent) { return }
        }
    } catch {
        Write-Warning "Install-WindowsFeature failed: $($_.Exception.Message)"
    }

    # Tier 2: inbox Feature-on-Demand capability (needs Windows Update online).
    try {
        if (Install-FromWindowsCapability) {
            Write-Output "Installed OpenSSH Server via Add-WindowsCapability"
            if (Test-SshdPresent) { return }
        }
    } catch {
        Write-Warning "Add-WindowsCapability failed: $($_.Exception.Message). Falling back to portable zip..."
    }

    # Tier 3: bundled Win32-OpenSSH portable zip (universal, offline).
    Install-FromPortableZip
}

function Get-SshdConfigPath {
    $programDataConfig = Join-Path $env:ProgramData "ssh\sshd_config"
    if (Test-Path -Path $programDataConfig) {
        return $programDataConfig
    }

    # Seed the active config from the portable install's default when missing.
    $defaultConfig = Join-Path $InstallDir "sshd_config_default"
    if (Test-Path -Path $defaultConfig) {
        $sshDir = Join-Path $env:ProgramData "ssh"
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Copy-Item -Path $defaultConfig -Destination $programDataConfig -Force
        return $programDataConfig
    }

    return $null
}

function Set-PasswordAuthentication {
    $sshdConfigPath = Get-SshdConfigPath
    if ($null -eq $sshdConfigPath) {
        Write-Warning "sshd_config not found; leaving default authentication settings"
        return
    }

    $passwordAuthSet = $false
    $lines = @(Get-Content -Path $sshdConfigPath)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*#?\s*PasswordAuthentication\s+') {
            $lines[$i] = "PasswordAuthentication yes"
            $passwordAuthSet = $true
        }
    }
    if (-not $passwordAuthSet) {
        $lines += "PasswordAuthentication yes"
    }
    Set-Content -Path $sshdConfigPath -Value $lines
}

function Add-SshFirewallRule {
    # Create an explicit inbound rule so SSH works even if the global firewall is
    # later re-enabled by policy.
    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        return
    }
    if (Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue) {
        return
    }

    New-NetFirewallRule -Name "sshd" -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 |
        Out-Null
}

function Configure-OpenSSHServer {
    Set-Service -Name "sshd" -StartupType Automatic

    # Start sshd first: on a fresh install sshd_config is generated on first start.
    Start-Service -Name "sshd"

    Set-PasswordAuthentication
    Add-SshFirewallRule

    Restart-Service -Name "sshd"
}

function Test-OpenSSHServer {
    if ($null -eq (Get-SshdExePath)) {
        throw "OpenSSH verification failed: sshd.exe not found"
    }

    $service = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
    if (($null -eq $service) -or ($service.Status -ne "Running")) {
        throw "OpenSSH verification failed: sshd service is not running"
    }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect("127.0.0.1", 22)
        if (-not $client.Connected) {
            throw "OpenSSH verification failed: cannot connect to 127.0.0.1:22"
        }
    } finally {
        $client.Close()
    }

    Write-Output "OpenSSH Server verified: sshd running and accepting connections on port 22"
}

try {
    Write-Output "Installing and configuring OpenSSH Server..."
    Install-OpenSSHServer
    Configure-OpenSSHServer
    Test-OpenSSHServer
    Write-Output "OpenSSH Server has been enabled"
    exit 0
} catch {
    Write-Error "Failed to install or configure OpenSSH Server: $($_.Exception.Message)"
    exit 1
}
