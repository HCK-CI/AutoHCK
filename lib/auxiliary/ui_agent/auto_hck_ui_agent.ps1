# UIAgent - Runs in the interactive Windows session (Session 1).
# Watches a queue directory for command files, executes them with
# full desktop access, and writes JSON results.
#
# Communication protocol:
#   Request:  C:\UIAgent\queue\<id>.ps1   (PowerShell script to execute)
#   Response: C:\UIAgent\queue\<id>.json  (JSON with exit_code, stdout, stderr)
#   The agent deletes the .ps1 after execution.

$ErrorActionPreference = 'Stop'

$QueueDir = 'C:\UIAgent\queue'
$LogFile  = 'C:\UIAgent\agent.log'
$PollIntervalMs = 500

function Write-AgentLog {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Initialize-Agent {
    if (-not (Test-Path $QueueDir)) {
        New-Item -ItemType Directory -Path $QueueDir -Force | Out-Null
    }
    if (-not (Test-Path (Split-Path $LogFile))) {
        New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null
    }

    # Clean up stale requests from a previous boot
    Get-ChildItem -Path $QueueDir -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-AgentLog "Agent started in session $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"

    # Signal to the host that initialization is complete and it's safe to submit commands
    [System.IO.File]::WriteAllText('C:\UIAgent\agent.ready', (Get-Date -Format 'o'))
}

# Runs a queued .ps1 in a child process, captures output, and writes
# a .json result that the host (UIExecutor) polls for.
function Invoke-QueuedCommand {
    param([System.IO.FileInfo]$ScriptFile)

    $id = [System.IO.Path]::GetFileNameWithoutExtension($ScriptFile.Name)
    $resultPath = Join-Path $QueueDir "$id.json"

    Write-AgentLog "Executing command: $id"

    $stdout = ''
    $stderr = ''
    $exitCode = 0

    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptFile.FullName 2>&1
        $ErrorActionPreference = $prevPref

        # Separate normal output from error records.
        $stdoutLines = @()
        $stderrLines = @()
        foreach ($line in $output) {
            if ($line -is [System.Management.Automation.ErrorRecord]) {
                $stderrLines += $line.ToString()
            } else {
                $stdoutLines += $line.ToString()
            }
        }
        $stdout = $stdoutLines -join "`n"
        $stderr = $stderrLines -join "`n"
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    }
    catch {
        $stderr = $_.Exception.Message
        $exitCode = 1
    }

    $result = @{
        id        = $id
        exit_code = $exitCode
        stdout    = $stdout
        stderr    = $stderr
        completed = (Get-Date -Format 'o')
    } | ConvertTo-Json -Depth 5

    try {
        [System.IO.File]::WriteAllText($resultPath, $result)
        Write-AgentLog "Command $id finished with exit code $exitCode"
    }
    finally {
        Remove-Item -Path $ScriptFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

# --- Main loop: poll the queue directory for new .ps1 requests ---
Initialize-Agent

while ($true) {
    try {
        $scripts = Get-ChildItem -Path $QueueDir -Filter '*.ps1' -ErrorAction SilentlyContinue |
            Sort-Object CreationTime

        foreach ($script in $scripts) {
            Invoke-QueuedCommand -ScriptFile $script
        }
    }
    catch {
        Write-AgentLog "Error in main loop: $_"
    }

    Start-Sleep -Milliseconds $PollIntervalMs
}
