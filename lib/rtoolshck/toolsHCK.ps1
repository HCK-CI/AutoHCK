<#
.SYNOPSIS
  toolsHCK: Powershell wrapper for HCK\HLK Studio API.
.DESCRIPTION
  A script tool set for HCK\HLK automation powered by HCK\HLK API provided with the Microsoft's Windows HCK\HLK Studio.
.NOTES
  Author:         Bishara AbuHattoum <Bishara@daynix.com>
  License:        BSD
#>

# server switch to inform the script is to run as a server
[CmdletBinding()]
param([Switch]$server, [Int]$port = 4000, [Int]$timeout = 60, [Int]$polling = 10)

if ($env:WTTSTDIO -like "*\Hardware Certification Kit\*") {
    $Studio = "hck"
    if ($env:PROCESSOR_ARCHITECTURE -ne "x86") {

        if (-Not $json) {
            Write-Warning "HCK script should be run under a 32bit PowerShell"
            Write-Host "Redirecting ..."
        }

        $PowerShell = [System.IO.Path]::Combine($PSHOME.tolower().replace("system32","sysWOW64"), "powershell.exe")

        $Params = [String]::Empty

        if ($server) {
            $Params += "-server -port $port -timeout $timeout -polling $polling"
        }

        $Invocation = "$PSCommandPath $Params"

        Invoke-Expression "Invoke-Command -ScriptBlock { $PowerShell -File $Invocation }"

        exit $LASTEXITCODE
    }
} else {
    $Studio = "hlk"
}

##
$Version = "0.7.3"
$MaxJsonDepth = 6
##

#
# Loading HCK\HLK libraries
try {
    if ([string]::IsNullOrEmpty($env:WTTSTDIO)) {
        throw "WTTSTDIO is not set; run toolsHCK from an environment where Windows HLK/HCK Studio defines this variable."
    }
    foreach ($dll in @(
            'microsoft.windows.kits.hardware.filterengine.dll',
            'microsoft.windows.kits.hardware.objectmodel.dll',
            'microsoft.windows.kits.hardware.objectmodel.dbconnection.dll',
            'microsoft.windows.kits.hardware.objectmodel.submission.dll',
            'microsoft.windows.kits.hardware.objectmodel.submission.package.dll')) {
        [System.Reflection.Assembly]::LoadFrom((Join-Path $env:WTTSTDIO $dll)) | Out-Null
    }
} catch {
    Write-Error "Failed to load HLK/HCK Studio assemblies: $($_.Exception.Message)"
    exit 1
}

#
# Task
function New-Task($name, $stage, $status, $taskerrormessage, $tasktype, $childtasks) {
    [pscustomobject]@{
        name              = $name
        stage             = $stage
        status            = $status
        taskerrormessage  = $taskerrormessage
        tasktype          = $tasktype
        childtasks        = $childtasks
    }
}

#
# PackageProgressInfo
function New-PackageProgressInfo($current, $maximum, $message) {
    [pscustomobject]@{
        current  = $current
        maximum  = $maximum
        message  = $message
    }
}

#
# ProjectPackage
function New-ProjectPackage($name, $projectpackagepath, $iserror, $actionMessages) {
    [pscustomobject]@{
        name               = $name
        projectpackagepath = $projectpackagepath
        iserror            = $iserror
        messages           = $actionMessages
    }
}

#
# TestResultLogsZip
function New-TestResultLogsZip($testname, $testid, $status, $logszippath) {
    [pscustomobject]@{
        testname    = $testname
        testid      = $testid
        status      = $status
        logszippath = $logszippath
    }
}

#
# TestResult
function New-TestResult($name, $completiontime, $scheduletime, $starttime, $status, $instanceid, $arefiltersapplied, $target, $tasks) {
    [pscustomobject]@{
        name               = $name
        completiontime     = $completiontime
        scheduletime       = $scheduletime
        starttime          = $starttime
        status             = $status
        instanceid         = $instanceid
        arefiltersapplied  = $arefiltersapplied
        target             = $target
        tasks              = $tasks
    }
}

#
# FilterResult
function New-FilterResult($appliedfilterson) {
    [pscustomobject]@{ appliedfilterson = $appliedfilterson }
}

#
# Test
function New-Test($name, $id, $testtype, $estimatedruntime, $requiresspecialconfiguration, $requiressupplementalcontent, $scheduleoptions, $status, $executionstate) {
    [pscustomobject]@{
        name                         = $name
        id                           = $id
        testtype                     = $testtype
        estimatedruntime             = $estimatedruntime
        requiresspecialconfiguration = $requiresspecialconfiguration
        requiressupplementalcontent  = $requiressupplementalcontent
        scheduleoptions              = $scheduleoptions
        status                       = $status
        executionstate               = $executionstate
    }
}

#
# ProductInstanceTarget
function New-ProductInstanceTarget($name, $key, $machine) {
    [pscustomobject]@{
        name    = $name
        key     = $key
        machine = $machine
    }
}

#
# ProductInstance
function New-ProductInstance($name, $osplatform, $targetedpool, $targets) {
    [pscustomobject]@{
        name          = $name
        osplatform    = $osplatform
        targetedpool  = $targetedpool
        targets       = $targets
    }
}

#
# Project
function New-Project($name, $creationtime, $modifiedtime, $status, $productinstances) {
    [pscustomobject]@{
        name               = $name
        creationtime       = $creationtime
        modifiedtime       = $modifiedtime
        status             = $status
        productinstances   = $productinstances
    }
}

#
# Target
function New-Target($name, $key, $type) {
    [pscustomobject]@{
        name = $name
        key  = $key
        type = $type
    }
}

#
# Machine
function New-Machine($name, $state, $lastheartbeat) {
    [pscustomobject]@{
        name          = $name
        state         = $state
        lastheartbeat = $lastheartbeat
    }
}

#
# Pool
function New-Pool($name, $machines) {
    [pscustomobject]@{
        name     = $name
        machines = $machines
    }
}

#
# ActionResult
function New-ActionResult($content, $exception = $null) {
    if ([String]::IsNullOrEmpty($exception)) {
        $props = @{ result = "Success" }
        if (-Not [String]::IsNullOrEmpty($content)) {
            $jsoncontent = (ConvertFrom-Json $content)
            if ($jsoncontent -is [System.Array]) {
                $props['content'] = @($jsoncontent)
            } else {
                $props['content'] = $jsoncontent
            }
        }
        return [pscustomobject]$props
    }
    $msg = if ([String]::IsNullOrEmpty($exception.InnerException)) { $exception.Message } else { $exception.InnerException.Message }
    return [pscustomobject]@{ result = "Failure"; message = $msg }
}

# Shared action helpers (interactive vs JSON mode, nested Usage blocks).
function Test-ToolsHCKHelpExit {
    param([switch]$Help, [Parameter(Mandatory)][scriptblock]$ShowUsage)
    if (-not $Help) { return $false }
    if (-not $json) {
        & $ShowUsage
        return $true
    }
    throw "Help requested, ignoring..."
}

function Assert-ToolsHCKNonEmptyParam {
    param(
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$MissingMessage,
        [Parameter(Mandatory)][scriptblock]$ShowUsage
    )
    if (-not [string]::IsNullOrEmpty($Value)) { return $true }
    if (-not $json) {
        Write-Output "WARNING: $MissingMessage"
        & $ShowUsage
        return $false
    }
    throw $MissingMessage
}

function Get-ToolsHCKChildPool {
    param(
        [Parameter(Mandatory)][string]$PoolName,
        [string]$IfNotFound
    )
    $wntdPool = $RootPool.GetChildPools() | Where-Object { $_.Name -eq $PoolName }
    if (-not $wntdPool) {
        if (-not [string]::IsNullOrEmpty($IfNotFound)) {
            throw $IfNotFound
        }
        throw "Did not find pool $PoolName in Root pool, aborting..."
    }
    $wntdPool
}

function Get-ToolsHCKMachineInPool {
    param(
        [Parameter(Mandatory)]$WntdPool,
        [Parameter(Mandatory)][string]$MachineName,
        [string]$IfNotFound
    )
    $wntdMachine = $WntdPool.GetMachines() | Where-Object { $_.Name -eq $MachineName }
    if (-not $wntdMachine) {
        if (-not [string]::IsNullOrEmpty($IfNotFound)) {
            throw $IfNotFound
        }
        throw "The test machine was not found, aborting..."
    }
    $wntdMachine
}

# ------------------------------------------------------------ #
# Functions, one for each action the script is able to perform #
# ------------------------------------------------------------ #
# ListPools
function listpools {
    [CmdletBinding()]
    param([Switch]$help)

    function Usage {
        Write-Output "listpools:"
        Write-Output ""
        Write-Output "A script that lists the pools info."
        Write-Output "and last heart beat."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "listpools [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output " help = Shows this message."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-Not $json) {
        foreach ($Pool in $RootPool.GetChildPools()) {
            Write-Output "============================================="
            Write-Output "Pool name : $($Pool.Name)"

            Write-Output ""

            $Machines = $Pool.GetMachines()

            if ($Machines.Count -lt 1) {
                Write-Output "    The pool is empty!"
            } else {
                Write-Output "    Machines :"

                foreach ($Machine in $Machines) {
                    Write-Output "        Name            : $($Machine.Name)"
                    Write-Output "        State           : $($Machine.Status)"
                    Write-Output "        Last heart beat : $($Machine.LastHeartBeat)"
                    Write-Output ""
                }
            }

            Write-Output "============================================="
        }
    } else {
        $poolslist = [System.Collections.Generic.List[object]]::new()
        foreach ($Pool in $RootPool.GetChildPools()) {
            $machineslist = [System.Collections.Generic.List[object]]::new()
            $Machines = $Pool.GetMachines()
            foreach ($Machine in $Machines) {
                $machineslist.Add((New-Machine $Machine.Name $Machine.Status.ToString() $Machine.LastHeartBeat.ToString()))
            }
            $poolslist.Add((New-Pool $Pool.Name $machineslist))
        }
        ConvertTo-Json @($poolslist) -Depth 3 -Compress
    }
}
#
# CreatePool
function createpool {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$pool)

    function Usage {
        Write-Output "createpool:"
        Write-Output ""
        Write-Output "A script that creates a pool."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "createpool <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "     help = Shows this message."
        Write-Output ""
        Write-Output " poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    if (-Not $json) { Write-Output "Creating pool $pool in Root pool." }
    $RootPool.CreateChildPool($pool) | Out-Null
}
#
# DeletePool
function deletepool {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$pool)

    function Usage {
        Write-Output "deletepool:"
        Write-Output ""
        Write-Output "A script that deletes a pool."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "deletepool <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "     help = Shows this message."
        Write-Output ""
        Write-Output " poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool -IfNotFound "Provided pool's name is not valid, aborting..."

    if (-Not $json) { Write-Output "Deleting pool $pool in Root pool." }
    $RootPool.DeleteChildPool($WntdPool)
}
#
# MoveMachine
function movemachine {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$machine, [Parameter(Position=2)][String]$from, [Parameter(Position=3)][String]$to)

    function Usage {
        Write-Output "movemachine:"
        Write-Output ""
        Write-Output "A script that moves a machine from one pool to another."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "movemachine <machine> <frompool> <topool> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "     help = Shows this message."
        Write-Output ""
        Write-Output "  machine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output ""
        Write-Output " frompool = The name of the source pool."
        Write-Output ""
        Write-Output "   topool = The name of the destination pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $from -MissingMessage "Please provide a source pool's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $to -MissingMessage "Please provide a destination pool's name." -ShowUsage { Usage })) { return }

    $WntdFromPool = Get-ToolsHCKChildPool -PoolName $from -IfNotFound "Provided source pool's name is not valid, aborting..."
    $WntdToPool = Get-ToolsHCKChildPool -PoolName $to -IfNotFound "Provided destination pool's name is not valid, aborting..."
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdFromPool -MachineName $machine -IfNotFound "Provided machine's name is not valid, aborting..."

    if (-Not $json) { Write-Output "Moving machine $($WntdMachine.Name) from $($WntdFromPool.Name) to $($WntdToPool.Name) pool." }
    $WntdFromPool.MoveMachineTo($WntdMachine, $WntdToPool)
}
#
# SetMachineState
function setmachinestate {
    [CmdletBinding()]
    param([Switch]$help, [Int]$timeout = -1, [Parameter(Position=1)][String]$machine, [Parameter(Position=2)][String]$pool, [Parameter(Position=3)][String]$state)

    function Usage {
        Write-Output "setmachinestate:"
        Write-Output ""
        Write-Output "A script that sets the state of a machine to Ready or NotReady."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "setmachinestate <machine> <poolname> <state> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "     help = Shows this message."
        Write-Output ""
        Write-Output "  machine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output ""
        Write-Output " poolname = The name of the pool."
        Write-Output ""
        Write-Output "    state = The state, Ready or NotReady."
        Write-Output ""
        Write-Output "  timeout = The operation's timeout in seconds, disabled by default."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $state -MissingMessage "Please provide a state." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool -IfNotFound "Provided pool's name is not valid, aborting..."
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine -IfNotFound "Provided machine's name is not valid, aborting..."
    if (-Not ($timeout -eq -1)) { $timeout = $timeout * 1000 }

    if (-Not $json) { Write-Output "Setting machine $($WntdMachine.Name) to $state state..." }
    switch ($state) {
        "Ready" {
            if (-Not $WntdMachine.SetMachineStatus([Microsoft.Windows.Kits.Hardware.ObjectModel.MachineStatus]::Ready, $timeout)) { throw "Unable to change machine state, timed out." }
        }
        "NotReady" {
            if (-Not $WntdMachine.SetMachineStatus([Microsoft.Windows.Kits.Hardware.ObjectModel.MachineStatus]::NotReady, $timeout))  { throw "Unable to change machine state, timed out." }
        }
        default {
            throw "Provided desired machine's state is not valid, aborting..."
        }
    }
}
#
# DeleteMachine
function deletemachine {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$machine, [Parameter(Position=2)][String]$pool)

    function Usage {
        Write-Output "deletemachine:"
        Write-Output ""
        Write-Output "A script that deletes a machine."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "deletemachine <machine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "     help = Shows this message."
        Write-Output ""
        Write-Output "  machine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output ""
        Write-Output " poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool -IfNotFound "Provided pool's name is not valid, aborting..."

    if (-Not $json) { Write-Output "Deleting machine $machine..." }
    $WntdPool.DeleteMachine($machine)
}
#
# ListMachineTargets
function listmachinetargets {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$machine, [Parameter(Position=2)][String]$pool)

    function Usage {
        Write-Output "listmachinetargets:"
        Write-Output ""
        Write-Output "A script that lists the target devices of a machine that are available to be tested."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "listmachinetargets <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "   poolname  = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine

    if (-Not $json) {
        Write-Output ""
        Write-Output "The tests targets on $($WntdMachine.Name) are:"
        Write-Output ""

        foreach ($TestTarget in $WntdMachine.GetTestTargets()) {
            Write-Output "============================================="
            Write-Output "Target name : $($TestTarget.Name)"
            Write-Output ""
            Write-Output "    Key  : $($TestTarget.Key)"
            Write-Output "    Type : $($TestTarget.TargetType)"
            Write-Output ""
            Write-Output "============================================="
        }
    } else {
        $targetslist = [System.Collections.Generic.List[object]]::new()
        foreach ($TestTarget in $WntdMachine.GetTestTargets()) {
            $targetslist.Add((New-Target $TestTarget.Name $TestTarget.Key $TestTarget.TargetType))
        }
        ConvertTo-Json @($targetslist) -Compress
    }
}
#
# ListProjects
function listprojects {
    [CmdletBinding()]
    param([Switch]$help)

    function Usage {
        Write-Output "listprojects:"
        Write-Output ""
        Write-Output "A script that lists the projects info."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "listprojects [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "      help = Shows this message."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-Not $json) {
        foreach ($ProjectName in $Manager.GetProjectNames()) {
            $Project = $Manager.GetProject($ProjectName)
            Write-Output "============================================="
            Write-Output "Project name : $($Project.Name)"

            Write-Output ""
            Write-Output "    Creation time : $($Project.CreationTime)"
            Write-Output "    Modified time : $($Project.ModifiedTime)"
            Write-Output "    Status        : $($Project.Info.Status)"
            Write-Output ""
            $ProductInstances = $Project.GetProductInstances()
            if ($ProductInstances.Count -lt 1) {
                Write-Output "    No product instances!"
            } else {
                Write-Output "    Product instances :"
                foreach ($Pi in $ProductInstances) {
                    Write-Output "        Name          : $($Pi.Name)"
                    Write-Output "        OSPlatform    : $($Pi.OSPlatform.Name)"
                    Write-Output "        Targeted pool : $($Pi.MachinePool.Name)"
                    Write-Output "        Targets       :"
                    foreach ($Target in $Pi.GetTargets()) {
                        Write-Output "            Name    : $($Target.Name)"
                        Write-Output "            Key     : $($Target.Key)"
                        Write-Output "            Type    : $($Target.TargetType)"
                        Write-Output "            Machine : $($Target.Machine.Name)"
                        Write-Output ""
                    }
                }
            }

            Write-Output "============================================="
        }
    } else {
        $projectslist = [System.Collections.Generic.List[object]]::new()
        foreach ($ProjectName in $Manager.GetProjectNames()) {
            $Project = $Manager.GetProject($ProjectName)
            $ProductInstances = $Project.GetProductInstances()
            $productinstanceslist = [System.Collections.Generic.List[object]]::new()
            foreach ($Pi in $ProductInstances) {
                $targetslist = [System.Collections.Generic.List[object]]::new()
                foreach ($Target in $Pi.GetTargets()) {
                    $targetslist.Add((New-ProductInstanceTarget $Target.Name $Target.Key $Target.Machine.Name))
                }
                $productinstanceslist.Add((New-ProductInstance $Pi.Name $Pi.OSPlatform.Name $Pi.MachinePool.Name $targetslist))
            }
            $projectslist.Add((New-Project $Project.Name $Project.CreationTime.ToString() $Project.ModifiedTime.ToString() $Project.Info.Status.ToString() $productinstanceslist))
        }
        ConvertTo-Json @($projectslist) -Depth 5 -Compress
    }
}
#
# CreateProject
function createproject {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$project)

    function Usage {
        Write-Output "createproject:"
        Write-Output ""
        Write-Output "A script that creates a project."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "createproject <projectname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "               help = Shows this message."
        Write-Output ""
        Write-Output "        projectname = The name of the project."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }

    if ($Manager.GetProjectNames().Contains($project)) {
        throw "A project with the name $($project) already exists, aborting..."
    } else {
        if (-Not $json) { Write-Output "Creating a new project named $($project)." }
        $WntdProject = $Manager.CreateProject($project)
    }
}
#
# DeleteProject
function deleteproject {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$project)

    function Usage {
        Write-Output "deleteproject:"
        Write-Output ""
        Write-Output "A script that deletes a project."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "deleteproject <projectname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "               help = Shows this message."
        Write-Output ""
        Write-Output "        projectname = The name of the project."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }

    if (-Not $json) { Write-Output "Deleting project $project..." }
    $Manager.DeleteProject($project)
}
#
# CreateProjectTarget
function createprojecttarget {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$target, [Parameter(Position=2)][String]$project, [Parameter(Position=3)][String]$machine, [Parameter(Position=4)][String]$pool)

    function Usage {
        Write-Output "createprojecttarget:"
        Write-Output ""
        Write-Output "A script that creates a project's target."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "createprojecttarget <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    $CreatedPI = $false
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) {
        if (-Not $WntdProject.CanCreateProductInstance($WntdMachine.OSPlatform.Description, $WntdPool, $WntdMachine.OSPlatform)) {
            throw "Can't create the project's product instance, it may be due to the project having another product instance that matches the wanted machine's pool or platform."
        } else {
            $WntdPI = $WntdProject.CreateProductInstance($WntdMachine.OSPlatform.Description, $WntdPool, $WntdMachine.OSPlatform)
            $CreatedPI = $true
        }
    }

    try {
        $WntdPITargets = $WntdPI.GetTargets()
        if (($WntdTarget.TargetType -eq "System") -and ($WntdPITargets | Where-Object { $_.TargetType -ne "System" })) { throw "The project already has non-system targets, can't mix system and non-system targets, aborting..." }
        if (($WntdTarget.TargetType -ne "System") -and ($WntdPITargets | Where-Object { $_.TargetType -eq "System" })) { throw "The project already has system targets, can't mix system and non-system targets, aborting..." }
        else {
            $WntdtoTarget = [System.Collections.Generic.List[object]]::new()
            if ($WntdTarget.TargetType -eq "TargetCollection") {
                foreach ($toTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
                    if ($toTarget.Machine.Equals($WntdMachine)){
                        $WntdtoTarget.Add($toTarget)
                    }
                }
            } else {
                $WntdtoTarget.Add($WntdTarget)
            }
            if ($WntdtoTarget.Count -lt 1) { throw "No targets to create were found, aborting..." }
            foreach ($toTarget in $WntdtoTarget) {
                if ($WntdPITargets | Where-Object { ($_.Key -eq $toTarget.Key) -and $_.Machine.Equals($toTarget.Machine) }) { continue }

                switch ($toTarget.TargetType) {
                    "Filter" { [String[]]$HardwareIds = $toTarget.Key }
                    "System" { [String[]]$HardwareIds = "[SYSTEM]" }
                    default { [String[]]$HardwareIds = $toTarget.HardwareId }
                }
                if (-Not ($WntdDeviceFamily = $Manager.GetDeviceFamilies() | Where-Object { $_.Name -eq $HardwareIds[0] })) {
                    $WntdDeviceFamily = $Manager.CreateDeviceFamily($HardwareIds[0], $HardwareIds)
                }

                if ($WntdPITargets | Where-Object { ($_.Key -eq $toTarget.Key) }) {
                    $WntdTargetFamily = ($WntdPITargets | Where-Object { ($_.Key -eq $toTarget.Key) })[0].TargetFamily
                } else {
                    $WntdTargetFamily = $WntdPI.CreateTargetFamily($WntdDeviceFamily)
                }

                if (-Not $json) { Write-Output "Creating a new project's target from $($toTarget.Name)." }

                $WntdTargetFamily.CreateTarget($toTarget) | Out-Null
            }
        }
    } catch {
        if ($CreatedPI) { $WntdProject.DeleteProductInstance($WntdMachine.OSPlatform.Description) }
        throw
    }
}
#
# DeleteProjectTarget
function deleteprojecttarget {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$target, [Parameter(Position=2)][String]$project, [Parameter(Position=3)][String]$machine, [Parameter(Position=4)][String]$pool)

    function Usage {
        Write-Output "deleteprojecttarget:"
        Write-Output ""
        Write-Output "A script that deletes a project's target."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "deleteprojecttarget <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdtoDelete = [System.Collections.Generic.List[object]]::new()
    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($toDelete in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $toDelete.Key) -and ($_.Machine.Equals($toDelete.Machine)) } | foreach { $WntdtoDelete.Add($_) }
        }
    } else {
        $WntdtoDelete.Add($WntdTarget)
    }
    foreach ($toDelete in $WntdtoDelete) {
        if (-Not $json) { Write-Output "Deleting a new project's target from $($toDelete.Name)." }
        $WntdPI.DeleteTarget($toDelete.Key, $toDelete.Machine)
    }

    if ($WntdPI.GetTargets().Count -lt 1) { $WntdProject.DeleteProductInstance($WntdPI.Name) }
}

function parsescheduleoptions {
    [CmdletBinding()]
    param([Microsoft.Windows.Kits.Hardware.ObjectModel.DistributionOption] $scheduleoptions)

    $do = [Microsoft.Windows.Kits.Hardware.ObjectModel.DistributionOption]
    $ParsedScheduleOptions = [System.Collections.Generic.List[string]]::new()
    foreach ($flag in @(
            $do::RequiresMultipleMachines,
            $do::ScheduleOnAllTargets,
            $do::ScheduleOnAnyTarget,
            $do::ConsolidateScheduleAcrossTargets
        )) {
        if (($scheduleoptions -band $flag) -eq $flag) {
            $ParsedScheduleOptions.Add($flag.ToString())
        }
    }
    return ,$ParsedScheduleOptions
}

#
# ListTests
function listtests {
    [CmdletBinding()]
    param([Switch]$help, [Switch]$manual, [Switch]$auto, [Switch]$failed, [Switch]$inqueue, [Switch]$notrun, [Switch]$passed, [Switch]$running, [String]$playlist, [Parameter(Position=1)][String]$target, [Parameter(Position=2)][String]$project, [Parameter(Position=3)][String]$machine, [Parameter(Position=4)][String]$pool)

    function Usage {
        Write-Output "listtests:"
        Write-Output ""
        Write-Output "A script that lists a project target's tests."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "listtests <targetkey> <projectname> <testmachine> <poolname> [-manual]"
        Write-Output "                           [-auto] [-failed] [-inqueue] [-notrun] [-passed] [-running]"
        Write-Output "                               [-playlist] [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "    playlist = List only the tests that matches the given playlist, (by path)."
        Write-Output ""
        Write-Output "      manual = List only the manual run tests."
        Write-Output ""
        Write-Output "        auto = List only the auto run tests."
        Write-Output ""
        Write-Output "      failed = List only the failed tests."
        Write-Output ""
        Write-Output "     inqueue = List only the tests that are in the run queue."
        Write-Output ""
        Write-Output "      notrun = List only the tests that haven't been run."
        Write-Output ""
        Write-Output "      passed = List only the passed tests."
        Write-Output ""
        Write-Output "     running = List only the running tests."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }
    if ((-Not [String]::IsNullOrEmpty($playlist)) -and $Studio -ne "hlk") {
        if (-Not $json) {
            Write-Output "WARNING: Playlist provided but HCK doesn't support playlists, aborting..."
            Usage; return
        } else {
            throw "Playlist provided but HCK doesn't support playlists, aborting..."
        }
    }

    if (-Not ($manual -or $auto)) {
        $manual = $true
        $auto = $true
    }
    if (-Not ($notrun -or $failed -or $passed -or $running -or $inqueue)) {
        $notrun = $true
        $failed = $true
        $passed = $true
        $running = $true
        $inqueue = $true
    }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()

    if (-Not [String]::IsNullOrEmpty($playlist)) {
        $PlaylistManager = New-Object Microsoft.Windows.Kits.Hardware.ObjectModel.PlaylistManager $WntdProject
        $WntdPlaylist = [Microsoft.Windows.Kits.Hardware.ObjectModel.PlaylistManager]::DeserializePlaylist($playlist)
        foreach ($tTest in $PlaylistManager.GetTestsFromProjectThatMatchPlaylist($WntdPlaylist)) {
            if ($tTest.GetTestTargets() | Where-Object { $WntdPITargets.Contains($_) }) { $WntdTests.Add($tTest) }
        }
    } else {
        $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }
    }

    if (-Not $json) {
        Write-Output ""
        Write-Output "The requested project project target's tests:"
        Write-Output ""

        foreach ($tTest in $WntdTests) {
            if (-Not (($manual -and ($tTest.TestType -eq "Manual")) -or ($auto -and ($tTest.TestType -eq "Automated")))) {
                continue
            } elseif (-Not (($notrun -and ($tTest.Status -eq "NotRun")) -or ($failed -and ($tTest.Status -eq "Failed")) -or ($passed -and ($tTest.Status -eq "Passed")) -or ($running -and ($tTest.ExecutionState -eq "Running")) -or ($inqueue -and ($tTest.ExecutionState -eq "InQueue")))) {
                continue
            }
            Write-Output "============================================="
            Write-Output "Test name : $($tTest.Name)"
            Write-Output ""
            Write-Output "    Test id                        : $($tTest.Id)"
            Write-Output "    Test type                      : $($tTest.TestType)"
            Write-Output "    Estimated runtime              : $($tTest.EstimatedRuntime)"
            Write-Output "    Requires special configuration : $($tTest.RequiresSpecialConfiguration)"
            Write-Output "    Requires supplemental content  : $($tTest.RequiresSupplementalContent)"
            Write-Output "    Schedule options               : $((parsescheduleoptions($tTest.ScheduleOptions)) -Join ', ')"
            Write-Output "    Test status                    : $($tTest.Status)"
            Write-Output "    Execution State                : $($tTest.ExecutionState)"
            Write-Output ""
            Write-Output "============================================="
        }
    } else {
        $testslist = [System.Collections.Generic.List[object]]::new()
        foreach ($tTest in $WntdTests) {
            if (-Not (($manual -and ($tTest.TestType -eq "Manual")) -or ($auto -and ($tTest.TestType -eq "Automated")))) {
                continue
            } elseif (-Not (($notrun -and ($tTest.Status -eq "NotRun")) -or ($failed -and ($tTest.Status -eq "Failed")) -or ($passed -and ($tTest.Status -eq "Passed")) -or ($running -and ($tTest.ExecutionState -eq "Running")) -or ($inqueue -and ($tTest.ExecutionState -eq "InQueue")))) {
                continue
            }
            $testslist.Add((New-Test $tTest.Name $tTest.Id $tTest.TestType.ToString() $tTest.EstimatedRuntime.ToString() $tTest.RequiresSpecialConfiguration.ToString() $tTest.RequiresSupplementalContent.ToString() (parsescheduleoptions($tTest.ScheduleOptions)) $tTest.Status.ToString() $tTest.ExecutionState.ToString()))
        }
        ConvertTo-Json @($testslist) -Compress
    }
}
#
# LoadPlaylist
function loadplaylist {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$project, [Parameter(Position=2)][String]$playlist)

    function Usage {
        Write-Output "loadplaylist:"
        Write-Output ""
        Write-Output "A script that loads a playlist for a project."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "loadplaylist <projectname> <playlist> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output "    playlist = Path to the playlist file."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $playlist -MissingMessage "Please provide a path to a playlist file." -ShowUsage { Usage })) { return }
    if ($Studio -ne "hlk") {
        if (-Not $json) {
            Write-Output "WARNING: HCK doesn't support playlists, aborting..."
            Usage; return
        } else {
            throw "HCK doesn't support playlists, aborting..."
        }
    }

    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }

    $PlaylistManager = New-Object Microsoft.Windows.Kits.Hardware.ObjectModel.PlaylistManager($WntdProject)

    if (-Not $json) { Write-Output "Loading playlist $($playlist)..." }

    $PlaylistManager.LoadPlaylist($playlist) | Out-Null
}
#
# GetTestInfo
function gettestinfo {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$test, [Parameter(Position=2)][String]$target, [Parameter(Position=3)][String]$project, [Parameter(Position=4)][String]$machine, [Parameter(Position=5)][String]$pool)

    function Usage {
        Write-Output "gettestinfo:"
        Write-Output ""
        Write-Output "A script that gets a project target's test info."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "gettestinfo <testid> <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "      testid = The id of the test, use listtests action to get it."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $test -MissingMessage "Please provide a test's id." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()
    $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }

    if (-Not ($WntdTest = $WntdTests | Where-Object { $_.Id -eq $test })) { throw "Didn't find a test with the id given." }

    if (-Not $json) {
        Write-Output ""
        Write-Output "The requested project project target's test:"
        Write-Output ""
        Write-Output "============================================="
        Write-Output "Test name : $($WntdTest.Name)"
        Write-Output ""
        Write-Output "    Test id                        : $($WntdTest.Id)"
        Write-Output "    Test type                      : $($WntdTest.TestType)"
        Write-Output "    Estimated runtime              : $($WntdTest.EstimatedRuntime)"
        Write-Output "    Requires special configuration : $($WntdTest.RequiresSpecialConfiguration)"
        Write-Output "    Requires supplemental content  : $($WntdTest.RequiresSupplementalContent)"
        Write-Output "    Schedule options               : $((parsescheduleoptions($WntdTest.ScheduleOptions)) -Join ', ')"
        Write-Output "    Test status                    : $($WntdTest.Status)"
        Write-Output "    Execution State                : $($WntdTest.ExecutionState)"
        Write-Output ""
        Write-Output "============================================="
    } else {
        @((New-Test $WntdTest.Name $WntdTest.Id $WntdTest.TestType.ToString() $WntdTest.EstimatedRuntime.ToString() $WntdTest.RequiresSpecialConfiguration.ToString() $WntdTest.RequiresSupplementalContent.ToString() (parsescheduleoptions($WntdTest.ScheduleOptions)) $WntdTest.Status.ToString() $WntdTest.ExecutionState.ToString())) | ConvertTo-Json -Compress
    }
}
#
# QueueTest
function queuetest {
    [CmdletBinding()]
    param(
        [Switch]$help,
        [String]$sup,
        [String]$parameters,
        [String]$IPv6,
        [Parameter(Position=1)][String]$test,
        [Parameter(Position=2)][String]$target,
        [Parameter(Position=3)][String]$project,
        [Parameter(Position=4)][String]$machine,
        [Parameter(Position=5)][String]$pool
    )

    function Usage {
        Write-Output "queuetest:"
        Write-Output ""
        Write-Output "A script that queues a test, use listtestresults action to get the results."
        Write-Output "(if the test needs two machines to run use -sup flag)"
        Write-Output "(if the test needs the IPv6 address of the support machine use -IPv6 flag)"
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "queuetest <testid> <targetkey> <projectname> <testmachine> <poolname> [-sup <json>]"
        Write-Output "              [-IPv6 <address>] [-help] [-parameters <parameters>]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "      testid = The id of the test, use listtests action to get it."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "        IPv6 = The support machine's ""SupportDevice0"" IPv6 address."
        Write-Output ""
        Write-Output "  parameters = Additional parameters in JSON format '{ ParameterName1: ParameterValue, ParameterName2: ParameterValue2 }'."
        Write-Output ""
        Write-Output "         sup = A JSON object mapping HLK role names to arrays of machine names."
        Write-Output "               Roles not listed default to the primary test machine."
        Write-Output "               Example: '{""MC"":[""CL2""],""SC"":[""CL3""]}'"
        Write-Output "               NOTE: support machines should be in a READY state."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $test -MissingMessage "Please provide a test's id." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()
    $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }

    if (-Not ($WntdTest = $WntdTests | Where-Object { $_.Id -eq $test })) { throw "Didn't find a test with the id given." }

    if (-Not $json) { Write-Output "Queueing test $($WntdTest.Name)..." }

    if (-Not [String]::IsNullOrEmpty($IPv6)) {
        $WntdTest.SetParameter("WDTFREMOTESYSTEM", $IPv6, [Microsoft.Windows.Kits.Hardware.ObjectModel.ParameterSetAsDefault]::DoNotSetAsDefault) | Out-Null
    }

    if (-Not [String]::IsNullOrEmpty($parameters)) {
        $parametersHashtable = ConvertFrom-Json $parameters
        foreach ($parameter in $parametersHashtable.PSObject.Properties) {
            $WntdTest.SetParameter($parameter.Name, $parameter.Value, [Microsoft.Windows.Kits.Hardware.ObjectModel.ParameterSetAsDefault]::DoNotSetAsDefault) | Out-Null
        }
    }

    if (-Not [String]::IsNullOrEmpty($sup)) {
        $supData = ConvertFrom-Json $sup
        $MachineSet = $WntdTest.GetMachineRole()

        $roleAliases = @{ 'MasterClient' = 'MC'; 'StressClient' = 'SC' }

        foreach ($Role in $MachineSet.Roles) {
            $existing = [System.Collections.Generic.List[object]]::new()
            $existing.AddRange($Role.GetMachines())
            $existing | ForEach-Object { $Role.RemoveMachine($_) }

            $machineNames = $supData.PSObject.Properties[$Role.Name]
            if (-Not $machineNames -and $roleAliases.ContainsKey($Role.Name)) {
                $machineNames = $supData.PSObject.Properties[$roleAliases[$Role.Name]]
            }
            if ($machineNames) {
                foreach ($machineName in $machineNames.Value) {
                    if (-Not ($sm = $WntdPool.GetMachines() | Where-Object { $_.Name -eq $machineName.Trim() })) { throw "Machine '$machineName' for role '$($Role.Name)' was not found, aborting..." }
                    $Role.AddMachine($sm)
                }
            } else {
                # Roles not listed in $supData (e.g. "Client"/"SUT") default to the primary test machine.
                $Role.AddMachine($WntdMachine)
            }
        }

        $MachineSet.ApplyMachineDimensions()
        $WntdTest.QueueTest($MachineSet) | Out-Null
    } else {
        $WntdTest.QueueTest() | Out-Null
    }
}
#
# ApplyProjectFilters
function applyprojectfilters {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$project)

    function Usage {
        Write-Output "applyprojectfilters:"
        Write-Output ""
        Write-Output "A script that applies the filters on a project's test results."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "applyprojectfilters <projectname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }

    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }

    if (-Not $json) { Write-Output "Applying filters on project $($WntdProject.Name)..." }

    $WntdFilterEngine = New-Object Microsoft.Windows.Kits.Hardware.FilterEngine.DatabaseFilterEngine $Manager
    $WntdFilterResultDictionary = $WntdFilterEngine.Filter($WntdProject)
    $Count = 0
    foreach ($tFilterResultCollection in $WntdFilterResultDictionary.Values) {
        $Count += $tFilterResultCollection.Count
    }

    if (-Not $json) {
        Write-Output "Applied filters on $Count tasks."
    } else {
        @(New-FilterResult $Count) | ConvertTo-Json -Compress
    }
}
#
# ApplyTestResultsFilters
function applytestresultfilters {
    [CmdletBinding()]
    param([Switch]$help, [Parameter(Position=1)][String]$result, [Parameter(Position=2)][String]$test, [Parameter(Position=3)][String]$target, [Parameter(Position=4)][String]$project, [Parameter(Position=5)][String]$machine, [Parameter(Position=6)][String]$pool)

    function Usage {
        Write-Output "applytestresultfilters:"
        Write-Output ""
        Write-Output "A script that applies filters on a test result."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "applytestresultfilters <resultindex> <testid> <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " resultindex = The index of the test result, use listtestresults action to get it."
        Write-Output ""
        Write-Output "      testid = The id of the test, use listtests action to get it."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $result -MissingMessage "Please provide a test result's index." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $test -MissingMessage "Please provide a test's id." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()
    $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }

    if (-Not ($WntdTest = $WntdTests | Where-Object { $_.Id -eq $test })) { throw "Didn't find a test with the id given." }

    if (-Not ($WntdTest.GetTestResults().Count -ge 1)) { throw "The test hasn't been queued, can't find test results." } else { $WntdResult = $WntdTest.GetTestResults()[$result] }

    if (-Not $json) { Write-Output "Applying filters on test result..." }

    $WntdFilterEngine = New-Object Microsoft.Windows.Kits.Hardware.FilterEngine.DatabaseFilterEngine $Manager
    $WntdFilterResultCollection = $WntdFilterEngine.Filter($WntdResult)

    if (-Not $json) {
        Write-Output "Applied filters on $($WntdFilterResultCollection.Count) tasks."
    } else {
        @(New-FilterResult $WntdFilterResultCollection.Count) | ConvertTo-Json -Compress
    }
}
#
# ListTestResults
function listtestresults {
    [CmdletBinding()]
    param(
        [Switch]$help,
        [Parameter(Position=1)][AllowNull()][String]$testid,
        [Parameter(Position=2)][String]$target,
        [Parameter(Position=3)][String]$project,
        [Parameter(Position=4)][String]$machine,
        [Parameter(Position=5)][String]$pool
    )

    function Usage {
        Write-Output "listtestresults:"
        Write-Output ""
        Write-Output "A script that lists all of the test results (if testid specified) or "
        Write-Output "lists all of the results for all tests (if testid '$null') and lists them and their info."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "listtestresults <testid> <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output "      testid = The id of the test, use listtests action to get it."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()

    if ([String]::IsNullOrEmpty($testid)) {
        $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }
    } else {
        $WntdPITargets | foreach { $_.GetTests() } | Where-Object { $_.Id -eq $testid } | foreach { $WntdTests.Add($_) }
        if ($WntdTests.Count -lt 1) { throw "Didn't find a test with the id given." }
        if ($WntdTests[0].GetTestResults().Count -lt 1) { throw "The test hasn't been queued, can't find test results." }
    }

    $testresultlist = [System.Collections.Generic.List[object]]::new()
    foreach ($WntdTest in $WntdTests) {
        $WntdResults = $WntdTest.GetTestResults()

        if (-Not $json) {
            Write-Output ""
            Write-Output "The requested project test's results:"
            Write-Output "Test name: $($WntdTest.Name)"
            Write-Output ""

            foreach ($tTestResult in $WntdResults) {
                $tTestResult.Refresh()
                Write-Output "============================================="
                Write-Output "Test result index : $($WntdResults.IndexOf($tTestResult))"
                Write-Output ""
                Write-Output "    Test name           : $($tTestResult.Test.Name)"
                Write-Output "    Completion time     : $($tTestResult.CompletionTime)"
                Write-Output "    Schedule time       : $($tTestResult.ScheduleTime)"
                Write-Output "    Start time          : $($tTestResult.StartTime)"
                Write-Output "    Status              : $($tTestResult.Status)"
                Write-Output "    Are filters applied : $($tTestResult.AreFiltersApplied)"
                Write-Output "    Target name         : $($tTestResult.Target.Name)"
                Write-Output "    Tasks               :"
                foreach ($tTask in $tTestResult.GetTasks()) {
                    Write-Output "        $($tTask.Name):"
                    Write-Output "            Stage              : $($tTask.Stage)"
                    Write-Output "            Status             : $($tTask.Status)"
                    if (-Not [String]::IsNullOrEmpty($tTask.TaskErrorMessage)) {
                        Write-Output "            Task error message : $($tTask.TaskErrorMessage)"
                    }
                    Write-Output "            Task type          : $($tTask.TaskType)"
                    if ($tTask.GetChildTasks()) {
                        Write-Output "            Sub tasks          :"

                        foreach ($subtTask in $tTask.GetChildTasks()) {
                            Write-Output "                $($subtTask.Name):"
                            Write-Output "                    Stage              : $($subtTask.Stage)"
                            Write-Output "                    Status             : $($subtTask.Status)"
                            if (-Not [String]::IsNullOrEmpty($subtTask.TaskErrorMessage)) {
                                Write-Output "                    Task error message : $($subtTask.TaskErrorMessage)"
                            }
                            Write-Output "                    Task type          : $($subtTask.TaskType)"
                            if (-Not ($subtTask -eq $tTask.GetChildTasks()[-1])) {
                                Write-Output ""
                            }
                        }
                    }
                    Write-Output ""
                }
                Write-Output "============================================="
            }
        } else {
            foreach ($tTestResult in $WntdResults) {
                $tTestResult.Refresh()
                $taskslist = [System.Collections.Generic.List[object]]::new()

                foreach ($tTask in $tTestResult.GetTasks()) {
                    $subtaskslist = [System.Collections.Generic.List[object]]::new()

                    if ($tTask.GetChildTasks()) {
                        foreach ($subtTask in $tTask.GetChildTasks()) {
                            $subtasktype = (New-Task $subtTask.Name $subtTask.Stage $subtTask.Status.ToString() $subtTask.TaskErrorMessage $subtTask.TaskType ([System.Collections.Generic.List[object]]::new()))
                            $subtaskslist.Add($subtasktype)
                        }
                    }
                    $tasktype = (New-Task $tTask.Name $tTask.Stage $tTask.Status.ToString() $tTask.TaskErrorMessage $tTask.TaskType $subtaskslist)
                    $taskslist.Add($tasktype)
                }

                $testresultlist.Add((New-TestResult $tTestResult.Test.Name $tTestResult.CompletionTime.ToString() $tTestResult.ScheduleTime.ToString() $tTestResult.StartTime.ToString() $tTestResult.Status.ToString() $tTestResult.InstanceId.ToString() $tTestResult.AreFiltersApplied.ToString() $tTestResult.Target.Name $taskslist))
            }
        }
    }

    if ($json) {
        ConvertTo-Json @($testresultlist) -Depth $MaxJsonDepth -Compress
    }
}
#
# ZipTestResultLogs
function ziptestresultlogs {
    [CmdletBinding()]
    param(
        [Switch]$help,
        [Switch]$indexinstanceid,
        [Parameter(Position=1)][String]$resultindex,
        [Parameter(Position=2)][String]$test,
        [Parameter(Position=3)][String]$target,
        [Parameter(Position=4)][String]$project,
        [Parameter(Position=5)][String]$machine,
        [Parameter(Position=6)][String]$pool
    )

    function Usage {
        Write-Output "ziptestresultlogs:"
        Write-Output ""
        Write-Output "A script that zips a test result's logs to the returned zip file path."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "ziptestresultlogs <resultindex> <testid> <targetkey> <projectname> <testmachine> <poolname> [-help]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " resultindex = The index of the test result, use listtestresults action to get it."
        Write-Output ""
        Write-Output "      testid = The id of the test, use listtests action to get it."
        Write-Output ""
        Write-Output "    targetkey = The key of the target, use listmachinetargets to get it."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output " testmachine = The name of the machine as registered with the HCK\HLK controller."
        Write-Output "               NOTE: test machine should be in a READY state."
        Write-Output ""
        Write-Output "    poolname = The name of the pool."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $resultindex -MissingMessage "Please provide a test result's index." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $test -MissingMessage "Please provide a test's id." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $target -MissingMessage "Please provide a target's key." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $machine -MissingMessage "Please provide a machine's name." -ShowUsage { Usage })) { return }
    if (-not (Assert-ToolsHCKNonEmptyParam -Value $pool -MissingMessage "Please provide a pool's name." -ShowUsage { Usage })) { return }

    $WntdPool = Get-ToolsHCKChildPool -PoolName $pool
    $WntdMachine = Get-ToolsHCKMachineInPool -WntdPool $WntdPool -MachineName $machine
    if (-Not ($WntdTarget = $WntdMachine.GetTestTargets() | Where-Object { $_.Key -eq $target })) { throw "A target that matches the target's key given was not found in the specified machine, aborting..." }
    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }
    if (-Not ($WntdPI = $WntdProject.GetProductInstances() | Where-Object { $_.OSPlatform -eq $WntdMachine.OSPlatform })) { throw "Machine pool not targeted in the project." }

    $WntdPITargets = [System.Collections.Generic.List[object]]::new()

    if ($WntdTarget.TargetType -eq "TargetCollection") {
        foreach ($tTarget in $WntdPI.FindTargetFromContainer($WntdTarget.ContainerId)) {
            $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $tTarget.Key) -and ($_.Machine.Equals($tTarget.Machine)) } | foreach { $WntdPITargets.Add($_) }
        }
        if ($WntdPITargets.Count -lt 1) { throw "The target is not being targeted by the project." }
    } else {
        if (-Not ($WntdPITarget = $WntdPI.GetTargets() | Where-Object { ($_.Key -eq $WntdTarget.Key) -and ($_.Machine.Equals($WntdMachine)) })) { throw "The target is not being targeted by the project." }
        $WntdPITargets.Add($WntdPITarget)
    }

    $WntdTests = [System.Collections.Generic.List[object]]::new()
    $WntdPITargets | foreach { $WntdTests.AddRange($_.GetTests()) }

    if (-Not ($WntdTest = $WntdTests | Where-Object { $_.Id -eq $test })) { throw "Didn't find a test with the id given." }

    if ($indexinstanceid) {
        if (-Not ($WntdResult = $WntdTest.GetTestResults() | Where-Object { $_.InstanceId -eq $resultindex }))
            { throw "Invalid test result instance id, can't find the test result." } else { $WntdLogs = $WntdResult.GetLogs() }
    } else {
        if (-Not ($WntdResult = $WntdTest.GetTestResults()[$resultindex]))
            { throw "Invalid test result index, can't find the test result." } else { $WntdLogs = $WntdResult.GetLogs() }
    }
    if (-Not ($WntdLogs.Count -ge 1)) { throw "There are no logs to be zipped in the test result." }

    $DayStamp = $(get-date).ToString("dd-MM-yyyy")
    $TimeStamp = $(get-date).ToString("hh_mm_ss")

    $SafeTestName = ($WntdTest.Name -replace '[^\w\-\.]', '_').Trim('_')

    $LogsDir = $env:TEMP + "\prometheus_test_logs\$DayStamp\[$TimeStamp]" + $WntdTest.Id
    $ZipPath = $env:TEMP + "\prometheus_test_logs\$DayStamp\$DayStamp" + "_" + $TimeStamp + "_" + $WntdResult.InstanceId + "_" + $SafeTestName + ".zip"

    if (-Not $json) {
        Write-Output "The test has $($WntdResult.Status)!."
        Write-Output "Logs zipped to $ZipPath"
    }
    foreach ($Log in $WntdLogs) {
        $Log.WriteLogTo([System.IO.Path]::Combine($LogsDir, $Log.LogType, $Log.Name))
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($LogsDir, $ZipPath)
    if ($json) {
        @(New-TestResultLogsZip $WntdTest.Name $WntdTest.Id $WntdResult.Status.ToString() $ZipPath) | ConvertTo-Json -Compress
    }
}
#
# CreateProjectPackage
function createprojectpackage {
    [CmdletBinding()]
    param([Switch]$help, [Switch]$rph, [Switch]$removedriversignatures, [String]$playlist, [Parameter(Position=1)][String]$project, [Parameter(Position=2)][String]$package, [String]$driver, [String]$supplemental)

    function Usage {
        Write-Output "createprojectpackage:"
        Write-Output ""
        Write-Output "A script that creates a project's package and saves it to a file at <package> if used,"
        Write-Output "if not to %TEMP%\prometheus_packages\..."
        Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
        Write-Output ""
        Write-Output "Usage:"
        Write-Output ""
        Write-Output "createprojectpackage <projectname> [<package>] [-help] [-playlist] [-driver <path>] [-supplemental <path>] [-rph] [-removedriversignatures]"
        Write-Output ""
        Write-Output "Any parameter in [] is optional."
        Write-Output ""
        Write-Output "        help = Shows this message."
        Write-Output ""
        Write-Output " projectname = The name of the project."
        Write-Output ""
        Write-Output "     package = The path to the output package file."
        Write-Output ""
        Write-Output "    playlist = Path to the playlist file."
        Write-Output ""
        Write-Output "      driver = Path to the driver to add to the package."
        Write-Output ""
        Write-Output " supplemental = Path to supplemental files to add to the package."
        Write-Output ""
        Write-Output "        rph = Enable progress action handler (interactive package progress)."
        Write-Output ""
        Write-Output "removedriversignatures = Remove driver signatures before packaging (default: do not remove)."
        Write-Output ""
        Write-Output "With [json], output is JSON with name, projectpackagepath, iserror, and messages."
        Write-Output ""
        Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
    }

    if (Test-ToolsHCKHelpExit -Help:$help -ShowUsage { Usage }) { return }

    if (-not (Assert-ToolsHCKNonEmptyParam -Value $project -MissingMessage "Please provide a project's name." -ShowUsage { Usage })) { return }

    if (-Not ($Manager.GetProjectNames().Contains($project))) { throw "No project with the given name was found, aborting..." } else { $WntdProject = $Manager.GetProject($project) }

    [Int]$global:Steps = 1
    if ($server) {
        $global:StepsArray = [System.Collections.Generic.List[object]]::new()
    }

    [Action[Microsoft.Windows.Kits.Hardware.ObjectModel.Submission.PackageProgressInfo]]$action = {
        param([Microsoft.Windows.Kits.Hardware.ObjectModel.Submission.PackageProgressInfo]$progressinfo)

        if (($progressinfo.Current -eq 0) -and ($progressinfo.Maximum -eq 0)) {
            $jsonprogressinfo = @(New-PackageProgressInfo $progressinfo.Current $progressinfo.Maximum $progressinfo.Message) | ConvertTo-Json -Compress
            if ($server) {
                $global:StepsArray.Add($jsonprogressinfo)
            }
            Write-Host $jsonprogressinfo
        } else {
            if ($global:Steps -lt $progressinfo.Current) {
                if ($server) {
                    $JoinedSteps = $global:StepsArray -join [Environment]::NewLine
                    $global:StepsArray.Clear()
                    sendtcpsocket($JoinedSteps)
                    [Int]$global:Steps = receivetcpsocket
                } else {
                    Write-Host -NoNewline "toolsHCK@$($ControllerName):createprojectpackage($project)> "
                    [Int]$global:Steps = Read-Host
                }
            }
            $jsonprogressinfo = @(New-PackageProgressInfo $progressinfo.Current $progressinfo.Maximum $progressinfo.Message) | ConvertTo-Json -Compress
            if ($server) {
                $global:StepsArray.Add($jsonprogressinfo)
            }
            Write-Host $jsonprogressinfo
        }
    }

    $actionMessages = @()
    $iserror = $false

    $PlaylistManager = $null
    if (-Not [String]::IsNullOrEmpty($playlist)) {
        $PlaylistManager = New-Object Microsoft.Windows.Kits.Hardware.ObjectModel.PlaylistManager($WntdProject)

        if (-Not $json) {
            Write-Output "Loading playlist $($playlist)..."
        } else {
            $actionMessages += "Loading playlist $($playlist)..."
        }

        $PlaylistManager.LoadPlaylist($playlist) | Out-Null
    }

    if (-Not [String]::IsNullOrEmpty($package)) {
        $PackagePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($package)
    } else {
        if (-Not (Test-Path ($env:TEMP + "\prometheus_packages\"))) { New-Item ($env:TEMP + "\prometheus_packages\") -ItemType Directory | Out-Null }
        $PackagePath = $env:TEMP + "\prometheus_packages\" + $(get-date).ToString("dd-MM-yyyy") + "_" + $(get-date).ToString("hh_mm_ss") + "_" + $WntdProject.Name + "." + $Studio + "x"
    }
    $PackageWriter = New-Object Microsoft.Windows.Kits.Hardware.ObjectModel.Submission.PackageWriter $WntdProject

    # Add driver files to package if specified
    if (-Not [String]::IsNullOrEmpty($driver)) {
        $driver = [System.IO.Path]::GetFullPath($driver)
        if (Test-Path $driver) {
            # Collect all targets from the project
            $AllTargets = New-Object System.Collections.Generic.List[Microsoft.Windows.Kits.Hardware.ObjectModel.Target]
            foreach ($Pi in $WntdProject.GetProductInstances()) {
                foreach ($Target in $Pi.GetTargets()) {
                    $AllTargets.Add($Target)
                }
            }

            if ($AllTargets.Count -gt 0) {
                # Create ReadOnlyCollection<Target>
                $TargetArray = [Microsoft.Windows.Kits.Hardware.ObjectModel.Target[]]$AllTargets.ToArray()
                $TargetList = New-Object 'System.Collections.ObjectModel.ReadOnlyCollection[Microsoft.Windows.Kits.Hardware.ObjectModel.Target]' (,$TargetArray)

                # Create ReadOnlyCollection<String> for locales
                $LocaleArray = [string[]]@("English")
                $LocaleList = New-Object 'System.Collections.ObjectModel.ReadOnlyCollection[string]' (,$LocaleArray)

                # Create StringCollection instances for out parameters
                $ErrorMessages = New-Object System.Collections.Specialized.StringCollection
                $WarningMessages = New-Object System.Collections.Specialized.StringCollection

                # Separate symbols (.pdb files) from the driver directory
                $symbolPath = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $symbolPath | Out-Null
                Get-ChildItem -Path $driver -Filter *.pdb -Recurse | ForEach-Object { Move-Item -Path $_.FullName -Destination $symbolPath -Force }

                # Remove driver signatures before packaging to avoid embedded company signatures (only when -removeDriverSignatures)
                if ($removedriversignatures) {
                    Get-ChildItem -Path $driver -Include *.sys, *.dll, *.exe -Recurse | ForEach-Object {
                        if (-Not $json) {
                            Write-Output "Removing signature from file '$($_.FullName)' before packaging"
                        } else {
                            $actionMessages += "Removing signature from file '$($_.FullName)' before packaging"
                        }

                        $process = Start-Process -Wait -FilePath "$env:WTTSTDIO\..\Tests\amd64\Signtool.exe" -ArgumentList 'remove', '/s', $_.FullName -PassThru
                        if ($process.ExitCode -ne 0) {
                            $iserror = $true
                            if (-Not $json) {
                                Write-Output "Warning: Failed to remove signature from file '$($_.FullName)'. Signtool exit code: $($process.ExitCode)"
                            } else {
                                $actionMessages += "Warning: Failed to remove signature from file '$($_.FullName)'. Signtool exit code: $($process.ExitCode)"
                            }
                        }
                    }
                }

                $AddDriverResult = $PackageWriter.AddDriver($driver, $symbolPath, $TargetList, $LocaleList, [ref]$ErrorMessages, [ref]$WarningMessages)

                if (-Not $json) {
                    if ($AddDriverResult) {
                        Write-Output "Driver added to package from $driver"
                    } else {
                        $iserror = $true
                        Write-Output "Warning: Driver signability check did not pass"
                        foreach ($err in $ErrorMessages) { Write-Output "  Error: $err" }
                        foreach ($warn in $WarningMessages) { Write-Output "  Warning: $warn" }
                    }
                } else {
                    if ($AddDriverResult) {
                        $actionMessages += "Driver added to package from $driver"
                    } else {
                        $iserror = $true
                        $actionMessages += "Warning: Driver signability check did not pass"
                        foreach ($err in $ErrorMessages) { $actionMessages += "Error: $err" }
                        foreach ($warn in $WarningMessages) { $actionMessages += "Warning: $warn" }
                    }
                }
            }
        }
    }

    # Add supplemental files to package if specified
    if (-Not [String]::IsNullOrEmpty($supplemental)) {
        if (Test-Path $supplemental) {
            $PackageWriter.AddSupplementalFiles($supplemental)
            if (-Not $json) {
                Write-Output "Supplemental files added from $supplemental"
            } else {
                $actionMessages += "Supplemental files added from $supplemental"
            }
        }
    }

    if ($rph) { $PackageWriter.SetProgressActionHandler($action) }
    $PackageWriter.Save($PackagePath)
    $PackageWriter.Dispose()

    if (-Not $json) {
        Write-Output "Packaged to $($PackagePath)..."
    } else {
        @(New-ProjectPackage $WntdProject.Name $PackagePath $iserror $actionMessages) | ConvertTo-Json -Compress
    }
}
#
# GetTimeStamp
function gettimestamp {
    $now = Get-Date
    return "[{0}_{1}]" -f $now.ToString("dd-MM-yyyy"), $now.ToString("hh_mm_ss")
}
#
# SendTCPSocket
function sendtcpsocket {
    [CmdletBinding()]
    param([String]$data)

    $LengthString = "$($data.Length.ToString())$([Environment]::NewLine)"
    $TCPStream.Write([System.Text.Encoding]::Ascii.GetBytes($LengthString), 0, $LengthString.Length)
    $TCPStream.Write([System.Text.Encoding]::Ascii.GetBytes($data), 0, $data.Length)
}
#
# ReceiveTCPSocket
function receivetcpsocket {
    while (-Not $TCPStream.DataAvailable) { Start-Sleep -Milliseconds $PollingSleep }
    $TCPStreamReader.ReadLine().TrimEnd()
}

#
# Usage
function Usage {
    Write-Output "A shell-like tool set for HCK\HLK with various purposes which covers several actions as"
    Write-Output "explained in the usage section below."
    Write-Output "These tasks are done by using the HCK\HLK API provided with the Windows HCK\HLK Studio."
    Write-Output ""
    Write-Output "Usage:"
    Write-Output ""
    Write-Output "Command: <action> <actionsparameters> [json]"
    Write-Output ""
    Write-Output "Any parameter in [] is optional."
    Write-Output ""
    Write-Output "              json = Output in JSON format."
    Write-Output ""
    Write-Output "            action = The action you want to execute."
    Write-Output ""
    Write-Output " actionsparameters = The action's parameters as explained in the action's usage."
    Write-Output "                     NOTE: use -help to show action's usage."
    Write-Output ""
    Write-Output "Actions list:"
    Write-Output ""
    Write-Output "                   help : Shows the help message."
    Write-Output ""
    Write-Output "              listpools : Lists the pools info."
    Write-Output ""
    Write-Output "             createpool : Creates a pool."
    Write-Output ""
    Write-Output "             deletepool : Deletes a pool."
    Write-Output ""
    Write-Output "            movemachine : Moves a machine from one pool to another."
    Write-Output ""
    Write-Output "        setmachinestate : Sets the state of a machine to Ready or NotReady."
    Write-Output ""
    Write-Output "          deletemachine : Deletes a machine"
    Write-Output ""
    Write-Output "     listmachinetargets : Lists the target devices of a machine that are available to be tested."
    Write-Output ""
    Write-Output "           listprojects : Lists the projects info."
    Write-Output ""
    Write-Output "          createproject : Creates a project."
    Write-Output ""
    Write-Output "          deleteproject : Deletes a project."
    Write-Output ""
    Write-Output "    createprojecttarget : Creates a project's target."
    Write-Output ""
    Write-Output "    deleteprojecttarget : Delete a project's target."
    Write-Output ""
    Write-Output "              listtests : Lists a project target's tests."
    Write-Output ""
    Write-Output "            gettestinfo : Gets a project target's test info."
    Write-Output ""
    Write-Output "              queuetest : Queues a test, use listtestresults to get the results."
    Write-Output ""
    Write-Output "    applyprojectfilters : Applies the filters on a project's test results."
    Write-Output ""
    Write-Output " applytestresultfilters : Applies the filters on a test result."
    Write-Output ""
    Write-Output "        listtestresults : Lists a test's results info."
    Write-Output ""
    Write-Output "      ziptestresultlogs : Zips a test result's logs."
    Write-Output ""
    Write-Output "   createprojectpackage : Creates a project's package."
    Write-Output ""
    Write-Output "           loadplaylist : Loads a playlist for a project into HLK Studio."
    Write-Output ""
    Write-Output "NOTE: For more information about every action use action's -help parameter!"
    Write-Output "NOTE: Windows HCK\HLK Studio should be installed on the machine running the script!"
}

# ----------------------------------------------------------------- #
# Choosing which action to perform by parsing the called parameters #
# ----------------------------------------------------------------- #
$toolsHCKlist = [System.Collections.Generic.List[string]]::new([string[]]@(
    "listpools",
    "createpool",
    "deletepool",
    "movemachine",
    "setmachinestate",
    "deletemachine",
    "listmachinetargets",
    "listprojects",
    "createproject",
    "deleteproject",
    "createprojecttarget",
    "deleteprojecttarget",
    "listtests",
    "gettestinfo",
    "queuetest",
    "applyprojectfilters",
    "applytestresultfilters",
    "listtestresults",
    "ziptestresultlogs",
    "createprojectpackage",
    "loadplaylist"
))

# -------------------------------------- #
# Trying to perform the requested action #
# -------------------------------------- #
$ConnectFileName = Join-Path -Path $env:WTTSTDIO -ChildPath "connect.xml"
Write-Output "Opening connection file $ConnectFileName"
$ConnectFile = [xml](Get-Content $ConnectFileName)

$ControllerName = $ConnectFile.Connection.GetAttribute("Server")
$DatabaseName = $ConnectFile.Connection.GetAttribute("Source")

Write-Output "Connecting to $ControllerName..."
$Manager = New-Object Microsoft.Windows.Kits.Hardware.ObjectModel.DBConnection.DatabaseProjectManager -Args $ControllerName, $DatabaseName
if ($Manager -eq $null) {
    Write-Output "Connecting to $ControllerName failed"
    exit 1
}


$RootPool = $Manager.GetRootMachinePool()
$DefaultPool = $RootPool.DefaultPool

if ($server) {
    Write-Output "Initializing server's TCP listener"
    try {
    $TCPListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse('0.0.0.0'), $port)
    $TCPListener.Start()
    } catch [System.Net.Sockets.SocketException] {
        Write-Output "Starting TCP listener failed due to: $_.Exception.Message"
        exit 1
    }

    Write-Output "Waiting for a TCP client connection on port $port..."
    $TCPClientTask = $TCPListener.AcceptTcpClientAsync()
    if ($TCPClientTask.Wait($timeout*1000)) {
        Write-Output "TCP client is connected"
        $TCPClient = $TCPClientTask.Result
    } else {
        Write-Output "Waiting for a TCP client connection has timed out after $timeout seconds"
        $TCPListener.Stop()
        exit 1
    }

    $TCPStream = $TCPClient.GetStream()
    $TCPStreamReader = New-Object System.IO.StreamReader $TCPStream, System.Text.ASCIIEncoding
    $PollingSleep = [Math]::Ceiling(1000 / $polling)

    Write-Host (gettimestamp) "sending START"
    sendtcpsocket("START")
}

while($true) {
    if ($server) {
        $cmdline = receivetcpsocket
        Write-Host (gettimestamp) "received ($cmdline), processing..."
    } else {
        Write-Host -NoNewline "toolsHCK@$ControllerName> "
        $cmdline = Read-Host
    }

    [System.Collections.ArrayList]$cmdlinelist = $cmdline.Split(" ")
    $json = $false
    if ($cmdlinelist.Contains("json")) {
        $json = $true
        $cmdlinelist.Remove("json")
    }

    $cmd = $cmdlinelist[0]
    $cmdlinelist.RemoveAt(0)
    $cmdargs = $cmdlinelist -join " "

    if ([String]::IsNullOrEmpty($cmd) -or $cmd -eq "help") {
        $output = Usage
    } elseif ($cmd -eq "version") {
        $output = "toolsHCK Version: $Version"
    } elseif ($cmd -eq "exit") {
        if ($server) {
            Write-Host (gettimestamp) "sending END"
            sendtcpsocket("END")
        }
        break;
    } elseif ($cmd -eq "ping") {
        $output = "pong"
    } elseif ($toolsHCKlist.Contains($cmd)) {
        try {
            $actionoutput = Invoke-Expression "$cmd $cmdargs"
            if (-Not $json) {
                $output = $actionoutput
            } else {
                $output = @(New-ActionResult $actionoutput) | ConvertTo-Json -Depth $MaxJsonDepth -Compress
            }
        } catch {
            if (-Not $json) {
                if ([String]::IsNullOrEmpty($_.Exception.InnerException)) {
                    $output = "WARNING: $($_.Exception.Message)"
                } else {
                    $output = "WARNING: $($_.Exception.InnerException.Message)"
                }
            } else {
                $output = New-ActionResult $null $_.Exception | ConvertTo-Json -Compress
            }
        }
    } else {
        $output = "No such action name, type help."
    }

    $JoinedOutput = $output -join [Environment]::NewLine

    if ($server) {
        Write-Host (gettimestamp) "sending result for ($cmdline):"
        Write-Host $JoinedOutput
        sendtcpsocket($JoinedOutput)
    } else {
        Write-Host $JoinedOutput
    }
}

if ($server) {
    $TCPStreamReader.Close()
    $TCPStream.Close()
    $TCPClient.Close()
    $TCPListener.Stop()
}
