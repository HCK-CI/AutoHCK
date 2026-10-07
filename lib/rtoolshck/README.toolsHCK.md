
# toolsHCK

toolsHCK is a powershell HCK/HLK controller API wrapper that wraps and exposes the API to users as a shell.

## Getting Started

Follow these instructions to start using toolsHCK.

### Prerequisites

You will need one of the following installed on the studio machine:
* [Windows Hardware Certification Kit](https://docs.microsoft.com/en-us/previous-versions/windows/hardware/hck)
* [Windows Hardware Lab Kit](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/windows-hardware-lab-kit)

## Usage

### Commands summary

| Action | Descriptions |
| ------ | ------------ |
| **help** | Shows the help message. |
| **listpools** | Lists the pools info. |
| **createpool** | Creates a pool. |
| **deletepool** | Deletes a pool. |
| **movemachine** | Moves a machine from one pool to another. |
| **setmachinestate** | Sets the state of a machine to Ready or NotReady. |
| **deletemachine** | Deletes a machine. |
| **listmachinetargets** | Lists the target devices of a machine that are available to be tested. |
| **listprojects** | Lists the projects info. |
| **createproject** | Creates a project. |
| **deleteproject** | Deletes a project. |
| **createprojecttarget** | Creates a project's target. |
| **deleteprojecttarget** | Deletes a project's target. |
| **listtests** | Lists a project target's tests. |
| **gettestinfo** | Gets a project target's test info. |
| **queuetest** | Queue's a test, use get_test_results to get the results. |
| **applyprojectfilters** | Applies the filters on a project's test results. |
| **applytestresultfilters** | Applies the filters on a test result. |
| **listtestresults** | Lists a test results info. |
| **ziptestresultlogs** | Zipps a test result's log and fetches the zip. |
| **createprojectpackage** | Creates a project's package. |

### Example usage

```
PS C:\> .\toolsHCK.ps1
Opening connection file C:\Program Files (x86)\Windows Kits\10\Hardware Lab Kit\Studio\connect.xml
Connecting to HLK-STUDIO...
toolsHCK@HLK-STUDIO> createpool 'test'
Creating pool test in Root pool.
toolsHCK@HLK-STUDIO> exit
PS C:\> 
```

For more info use help command or use help parameter of a command, example:
```
toolsHCK@HLK-STUDIO> createpool -help
```

## Authors

* **Bishara AbuHattoum**

