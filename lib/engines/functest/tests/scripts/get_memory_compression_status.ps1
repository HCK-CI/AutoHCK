  # Get memory compression status
  try {
      $status = Get-MMAgent | Select-Object -ExpandProperty MemoryCompression
      if ($status -eq $true) {
          Write-Output "PASS: Memory compression is ENABLED"
      } else {
          Write-Output "PASS: Memory compression is DISABLED"
      }   
  } catch {
      Write-Error "FAIL: Unable to get memory compression status: $_"
      exit 1
  }   

