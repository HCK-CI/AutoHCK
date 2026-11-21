  # Disable memory compression
  try {
      $currentStatus = Get-MMAgent | Select-Object -ExpandProperty MemoryCompression
      
      if ($currentStatus -eq $false) {
          Write-Output "PASS: Memory compression already disabled"
          exit 0
      }   
      
      Disable-MMAgent -MemoryCompression
      Start-Sleep -Seconds 2
      
      $newStatus = Get-MMAgent | Select-Object -ExpandProperty MemoryCompression
      if ($newStatus -eq $false) {
          Write-Output "PASS: Memory compression disabled successfully"
      } else {
          Write-Error "FAIL: Memory compression was not disabled"
          exit 1
      }   
  } catch {
      Write-Error "FAIL: Unable to disable memory compression: $_"
      exit 1
  }
