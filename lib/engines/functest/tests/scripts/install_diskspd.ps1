  # Avoid querying unavailable sources (for example, the Microsoft Store) on
  # non-interactive test guests.
  winget install Microsoft.DiskSpd --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
  if ($LASTEXITCODE -ne 0) {
      Write-Error "FAIL: DiskSpd installation failed with exit code $LASTEXITCODE"
      exit $LASTEXITCODE
  }

  Write-Output "PASS: DiskSpd installed successfully"
