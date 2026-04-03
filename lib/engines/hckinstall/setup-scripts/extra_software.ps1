$ErrorActionPreference = "Stop"

. "$PSScriptRoot\auxiliary.ps1"

function Get-ExtraSoftwareConfig {
    param ([PSCustomObject]$Directory)

    if ($KITTYPE -eq 'HCK') {
        $full_kit = "${KITTYPE}".ToLower()
    }
    else {
        $full_kit = "${KITTYPE}${HLKKITVER}".ToLower()
    }

    $config_list = @(
        "${Directory}\${full_kit}-config.json",
        "${Directory}\config.json"
    )

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
