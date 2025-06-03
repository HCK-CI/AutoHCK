# AutoHCK

[![CircleCI](https://circleci.com/gh/HCK-CI/AutoHCK.svg?style=svg)](https://circleci.com/gh/HCK-CI/AutoHCK)

AutoHCK is a tool for automating [HCK](https://docs.microsoft.com/en-us/windows/win32/w8cookbook/windows-hardware-certification-kit)/[HLK](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/), test frameworks for Windows hardware drivers (WHQL certification), doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

## What is WHQL
The Windows Hardware Quality Labs (WHQL) certification is intended to help ensure that hardware and drivers for devices meet certain quality and compatibility standards. By obtaining WHQL certification, a device manufacturer is able to demonstrate that their products have been tested and found to be compatible with the Windows operating system.
In general, the WHQL certification process can be helpful for both device manufacturers and users. For manufacturers, obtaining WHQL certification can help to ensure that their products will work properly with the Windows operating system, which can improve the user experience and help to build trust with customers.
For users, the WHQL certification process can help to ensure that the hardware and drivers they are using are of high quality and are compatible with the Windows operating system. This can help to reduce the risk of errors and other problems, and can help to improve the overall stability and performance of the user's system.
Overall, the WHQL certification process can be helpful in ensuring that hardware and drivers for devices are compatible with the Windows operating system and are of high quality. This can benefit both device manufacturers and users.


## Getting Started

See [Getting Started](Getting-Started.md) for more details

## Usage

Once everything is installed and configured, run `./bin/auto_hck` with these parameters:

```
Usage: auto_hck.rb [common options] <command> [command options]

        --verbose                    Enable verbose logging
        --config <override.json>     Path to custom override.json file
        --client_world_net           Attach world bridge to clients VM
        --client-ctrl-net-dev <client-ctrl-net-dev>
                                     Client VM control network device (make sure that driver is installed)
        --id <id>                    Set ID for AutoHCK run
    -v, --version                    Display version information and exit
        --share-on-host-path <path>  For using Transfer Network specify the directory to share on host machine
    -h, --help                       Show this message
Usage: auto_hck.rb test [test options]

    -p, --platform <platform_name>   Platform for run test
    -d, --drivers <drivers_list>     List of driver for run test
        --driver-path <driver_path>  Path to the location of the driver wanted to be tested
    -c, --commit <commit_hash>       Commit hash for CI status update
        --diff <diff_file>           Path to text file containing a list of changed source files
        --svvp                       Run SVVP tests for specified platform instead of driver tests
        --dump                       Create machines snapshots and generate scripts for run it manualy
        --gthb_context_prefix <gthb_context_prefix>
                                     Add custom prefix for GitHub CI results context
        --gthb_context_suffix <gthb_context_suffix>
                                     Add custom suffix for GitHub CI results context
        --playlist <playlist>        Use custom Microsoft XML playlist
        --select-test-names <select_test_names>
                                     Use custom user text playlist
        --reject-test-names <reject_test_names>
                                     Use custom CI text ignore list
        --triggers <triggers_file>   Path to text file containing triggers
        --reject-report-sections <reject_report_sections>
                                     List of section to reject from HTML results
                                     (use "--reject-report-sections=help" to list sections)
        --boot-device <boot_device>  VM boot device
        --allow-test-duplication     Allow run the same test several times.
                                     Works only with custom user text playlist.
                                     Test results table can be broken. (experimental)
        --manual                     Run AutoHCK in manual mode
        --package-with-playlist      Load playlist into HLKX project package
    -h, --help                       Show this message
Usage: auto_hck.rb install [install options]

        --debug                      Enable debug mode
    -p, --platform <platform_name>   Install VM for specified platform
    -f, --force                      Install all VM, replace studio if exist
        --skip_client                Skip client images installation
    -d, --drivers <drivers_list>     List of driver attach in install
        --driver-path <driver_path>  Path to the location of the driver wanted to be installed
    -h, --help                       Show this message
```

### Dump mode
(make sure that driver is installed)
In dump mode, AutoHCK generates bash script files for each VM with all preparation steps. You can edit these files, update the QEMU command line, and then run it.

### Manual mode

In manual mode, AutoHCK performs the following steps:
   - Run VMs
   - Configure HLK environment (if driver binary present)
   - Run selected tests (if driver binary present)
   - Stop automatic test runs and start waiting for a manual exit
   - Stop VMs and save all run logs

### Examples

```
bin/auto_hck test --drivers Balloon --platform Win10x86 --driver-path /home/hck-ci/balloon/win10/x86
bin/auto_hck test --drivers NetKVM --platform Win10x64 --driver-path /home/hck-ci/workspace --diff /path/to/diff.txt
bin/auto_hck test --drivers viostor --platform Win10x64 --driver-path /home/hck-ci/viostor --diff /path/to/diff.txt -c ec3da560827922e5a82486cf19cd9c27e95455a9
bin/auto_hck test --svvp --platform Win10x64 --driver-path /home/hck-ci/virtio-drv
bin/auto_hck test -d NetKVM -p Win10x64 --driver-path /home/hck-ci/virtio-drv --manual
bin/auto_hck test -d NetKVM -p Win10x64 --manual
bin/auto_hck install -p Win2019x64 --force
```

### Workspace

When starting AutoHCK a session workspace will be created inside the workspace directory configured in `config.json` at the path:
  + in test mode: `workspace/[engine-type]/[setup-manager]/[devices-list]-[platform]/[timestamp]/`
  + in test svvp mode: `workspace/[engine-type]/[setup-manager]/svvp-[platform]/[timestamp]/`
  + in install mode: `workspace/[engine-type]/[setup-manager]/[platform]/[timestamp]/`

Inside AutoHCK will save the following files:
* qcow2 snapshots of the backing setup images: `[filename]-snapshot.qcow2`
* AutoHCK log file: `[devices-list]-[platform].log`
* toolsHCK guest log file: `[timestamp]_toolsHCK.log`
* archived tests log files: `[timestamp]-[testid].zip`
* archived driver binary: `[devices-list]-[platform].zip`
* Executables: `pre_start_[id].sh` `QemuMachine[id]_CL[id].sh` `post_stop_[id].sh` to rerun test setup machines manually.
* HLKX/HCKX file (after tests session ended): `[devices-list]-[platform].hlkx`

## Utils

### Cleanup

This script deletes logs and snapshots from HCK runs that are more than 1 month old, the script can be run as a cron job in order to prevent autoHCK from filling the disk on the system.

## Authors

* **Lior Haim** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Bishara AbuHattoum** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Basil Salman** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Kostiantyn Kostiuk** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Vitalii Chulak** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
