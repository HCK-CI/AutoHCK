  # Enable memory compression
  try {
      $currentStatus = Get-MMAgent | Select-Object -ExpandProperty MemoryCompression
      
      if ($currentStatus -eq $true) {
          Write-Output "PASS: Memory compression already enabled"
          exit 0
      }   
      
      Enable-MMAgent -MemoryCompression
      Start-Sleep -Seconds 2
      
      $newStatus = Get-MMAgent | Select-Object -ExpandProperty MemoryCompression
      if ($newStatus -eq $true) {
          Write-Output "PASS: Memory compression enabled successfully"
      } else {
          Write-Error "FAIL: Memory compression was not enabled"
          exit 1
      }
  } catch {
      Write-Error "FAIL: Unable to enable memory compression: $_"
      exit 1
  }
