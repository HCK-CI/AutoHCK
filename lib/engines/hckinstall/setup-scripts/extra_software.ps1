$ErrorActionPreference = "Stop"

. "$PSScriptRoot\auxiliary.ps1"

function Get-ProcessorArchConfigName {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { return 'amd64' }
        'x86' { return 'x86' }
        'ARM64' { return 'arm64' }
        default { return $env:PROCESSOR_ARCHITECTURE.ToLower() }
    }
}

function Get-ArchConfigVariants {
    param ([String]$Arch)

    $archName = $Arch.ToLower()
    $variants = @($archName)
    if ($archName -eq 'amd64') { $variants += 'x64' }
    if ($archName -eq 'x64') { $variants += 'amd64' }

    return $variants | Select-Object -Unique
}

function Get-ExtraSoftwareConfig {
    param ([PSCustomObject]$Directory)

    if ($KITTYPE -eq 'HCK') {
        $full_kit = "${KITTYPE}".ToLower()
    }
    else {
        $full_kit = "${KITTYPE}${HLKKITVER}".ToLower()
    }

    $arch = Get-ProcessorArchConfigName
    $config_list = @()
    foreach ($archVariant in (Get-ArchConfigVariants $arch)) {
        $config_list += "${Directory}\${full_kit}-${archVariant}-config.json"
        $config_list += "${Directory}\${archVariant}-config.json"
    }
    $config_list += "${Directory}\${full_kit}-config.json"
    $config_list += "${Directory}\config.json"

    foreach ($config_name in $config_list) {
        if (Test-Path -Path "$config_name" -PathType Leaf) {
            return $(Get-Content -Raw -Path "$config_name" | ConvertFrom-Json)
        }
    }

    Write-Error "Failed to find any config files: $([System.String]::Join(" ", $config_list))"
}

function Install-ExtraSoftware {
    param ([PSCustomObject]$Config, [String]$Path)
    Write-Output "Processing: $Config"

    $arguments = $Config.install_args. `
        Replace('@sw_path@', $Path). `
        Replace('@file_name@', $Config.file_name). `
        Replace('@temp@', ${env:TEMP})

    Execute-Command -Path "$($Config.install_cmd)" -Arguments "$arguments"
}

function Install-ClientExtraSoftwareBeforeKit {
    Write-Output "Installing extra software before kit installation"

    Get-ChildItem -Path "$EXTRASOFTWAREDIRECTORY" -Directory | ForEach-Object {
        $config = Get-ExtraSoftwareConfig -Directory "$($_.FullName)"

        if ($config.install_dest -eq 'client' -And $config.install_time.kit -eq 'before') {
            Install-ExtraSoftware -Config $config -Path "$($_.FullName)"
        }
    }
}

function Install-ClientExtraSoftwareAfterKit {
    Write-Output "Installing extra software after kit installation"

    Get-ChildItem -Path "$EXTRASOFTWAREDIRECTORY" -Directory | ForEach-Object {
        $config = Get-ExtraSoftwareConfig -Directory "$($_.FullName)"

        if ($config.install_dest -eq 'client' -And $config.install_time.kit -eq 'after') {
            Install-ExtraSoftware -Config $config -Path "$($_.FullName)"
        }
    }
}

function Install-StudioExtraSoftwareBeforeKit {
    Write-Output "Installing extra software before kit installation"

    Get-ChildItem -Path "$EXTRASOFTWAREDIRECTORY" -Directory | ForEach-Object {
        $config = Get-ExtraSoftwareConfig -Directory "$($_.FullName)"

        if ($config.install_dest -eq 'studio' -And $config.install_time.kit -eq 'before') {
            Install-ExtraSoftware -Config $config -Path "$($_.FullName)"
        }
    }
}

function Install-StudioExtraSoftwareAfterKit {
    Write-Output "Installing extra software after kit installation"

    Get-ChildItem -Path "$EXTRASOFTWAREDIRECTORY" -Directory | ForEach-Object {
        $config = Get-ExtraSoftwareConfig -Directory "$($_.FullName)"

        if ($config.install_dest -eq 'studio' -And $config.install_time.kit -eq 'after') {
            Install-ExtraSoftware -Config $config -Path "$($_.FullName)"
        }
    }
}
