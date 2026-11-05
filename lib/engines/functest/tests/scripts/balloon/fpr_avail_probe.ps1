# Probe: print the available memory in MB (for capture_output steps).
$os = Get-CimInstance Win32_OperatingSystem
Write-Output ([math]::Round($os.FreePhysicalMemory / 1KB))
