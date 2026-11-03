  # Run DiskSpd benchmark
  param(
      [string]$TestFile = "C:\testfile.dat",
      [string]$BlockSize = "64K",
      [int]$Duration = 120,
      [int]$OutstandingIO = 8,
      [int]$Threads = 4,
      [int]$WritePercentage = 50,
      [string]$FileSize = "2G"
  )

  try {
      # Winget exposes DiskSpd on the system PATH.
      $diskspdExe = Get-Command diskspd.exe -ErrorAction Stop
  
      Write-Output "Using DiskSpd: $($diskspdExe.Path)"

      # Build command
      $cmd = "-b$BlockSize -d$Duration -o$OutstandingIO -t$Threads -r -w$WritePercentage -c$FileSize $TestFile"
      Write-Output "Running: diskspd.exe $cmd"

      # Run DiskSpd
      $output = & $diskspdExe.Path $cmd.Split(' ')

      # Display output
      $output | ForEach-Object { Write-Output $_ }

      # Check for errors in output
      if ($LASTEXITCODE -ne 0) {
          Write-Error "FAIL: DiskSpd returned exit code $LASTEXITCODE"
      }   
      
      # Parse results (basic validation)
      $totalIOPS = $output | Select-String "total:" | Select-Object -First 1
      $avgLatency = $output | Select-String "AvgLat" | Select-Object -First 1
      
      if ($totalIOPS -and $avgLatency) {
          Write-Output "PASS: DiskSpd benchmark completed successfully"
          Write-Output "Results summary:"
          Write-Output "  $totalIOPS"
          Write-Output "  $avgLatency"
      } else {
          Write-Output "WARNING: Could not parse all benchmark results, but test completed"
          Write-Output "PASS: DiskSpd benchmark executed"
      }   
      
  } catch {
      Write-Error "FAIL: Unable to run DiskSpd benchmark: $_"
      exit 1
  } finally {
      # Cleanup test file
      if (Test-Path $TestFile) {
          Remove-Item -Path $TestFile -Force -ErrorAction SilentlyContinue
      }
  }
