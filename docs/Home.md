# AutoHCK

[![CircleCI](https://circleci.com/gh/HCK-CI/AutoHCK.svg?style=svg)](https://circleci.com/gh/HCK-CI/AutoHCK)

AutoHCK is a tool for automating [HCK](https://docs.microsoft.com/en-us/windows/win32/w8cookbook/windows-hardware-certification-kit)/[HLK](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/), test frameworks for Windows hardware drivers (WHQL certification), doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

## What is WHQL

The Windows Hardware Quality Labs (WHQL) certification is intended to help ensure that hardware and drivers for devices meet certain quality and compatibility standards. By obtaining WHQL certification, a device manufacturer is able to demonstrate that their products have been tested and found to be compatible with the Windows operating system.

In general, the WHQL certification process can be helpful for both device manufacturers and users. For manufacturers, obtaining WHQL certification can help to ensure that their products will work properly with the Windows operating system, which can improve the user experience and help to build trust with customers.

For users, the WHQL certification process can help to ensure that the hardware and drivers they are using are of high quality and are compatible with the Windows operating system. This can help to reduce the risk of errors and other problems, and can help to improve the overall stability and performance of the user's system.

Overall, the WHQL certification process can be helpful in ensuring that hardware and drivers for devices are compatible with the Windows operating system and are of high quality. This can benefit both device manufacturers and users.


## Getting Started

See [Getting Started](Getting-Started.md) for prerequisites, dependency clones, configuration, and first-time validation steps.

## Usage

Once everything is installed and configured, run AutoHCK from the repository root:

```bash
bin/auto_hck <command> [options]
```

For all options, run:

```bash
bin/auto_hck --help
bin/auto_hck test --help
bin/auto_hck install --help
```

### CLI reference

The following matches `bin/auto_hck --help` (common options plus subcommand summaries):

```text
Usage: auto_hck.rb [common options] <command> [command options]

        --share-on-host-path <path>  For using Transfer Network specify the directory to share on host machine
        --verbose                    Enable verbose logging
        --config <override.json>     Path to custom override.json file
        --client_world_net           Attach world bridge to clients VM
        --client-ctrl-net-dev <client-ctrl-net-dev>
                                     Client VM control network device (make sure that driver is installed)
        --attach-debug-net           Attach debug network to all VMs
        --id <id>                    Set ID for AutoHCK run
    -v, --version                    Display version information and exit
    -w <path>                        Internal use only
        --whiteboard <text>          Custom text logged, added to HTML results and JUnit properties
    -h, --help                       Show this message
Usage: auto_hck.rb test [test options]

    -p, --platform <platform_name>   Platform for run test
    -d, --drivers <drivers_list>     List of driver for run test
        --driver-path <driver_path>  Path to the location of the driver wanted to be tested
        --supplemental-path <supplemental_path>
                                     Path to the supplemental content folder (e.g. for README)
        --package-with-driver [package_action]
                                     Include driver files in HLKX package (requires --driver-path)
                                     Use --package-with-driver or --package-with-driver=keep to include driver with original signature
                                     Use --package-with-driver=unsigned to remove signature from the driver before including
    -c, --commit <commit_hash>       Commit hash for CI status update
        --svvp                       Run SVVP tests for specified platform instead of driver tests
        --dump                       Create machines snapshots and generate scripts for run it manually
        --gthb_context_prefix <gthb_context_prefix>
                                     Add custom prefix for GitHub CI results context
        --gthb_context_suffix <gthb_context_suffix>
                                     Add custom suffix for GitHub CI results context
        --playlist <playlist>        Use custom Microsoft XML playlist
        --select-test-names <select_test_names>
                                     Use custom user text playlist
        --reject-test-names <reject_test_names>
                                     Use custom CI text ignore list
        --enable-vbs                 Enable VBS state for clients
        --reject-report-sections <reject_report_sections>
                                     List of section to reject from HTML results
                                     (use "--reject-report-sections=help" to list sections)
        --boot-device <boot_device>  VM boot device
        --allow-test-duplication     Allow run the same test several times.
                                     Works only with custom user text playlist.
                                     Test results table can be broken. (experimental)
        --manual                     Run AutoHCK in manual mode
        --auto-manual                Run AutoHCK in normal mode and switch to manual mode only when failure is detected
        --package-with-playlist      Load playlist into HLKX project package
        --tag-suffix <tag_suffix>    Add custom suffix to HCK-CI tag to prevent name conflicts when using shared controller
        --fs-test-image-format <fs_test_image_format>
                                     Filesystem test image format (qcow2/raw). Default is qcow2.
                                     Has effect only when testing storage drivers.
        --extensions <extensions_list>
                                     List of extensions for run test
        --net-test-speed <net_test_speed>
                                     Network test speed (in Mbps). Default is 10000.
                                     Has effect only when testing virtio-net-pci network device.
        --auto-retry-failed-tests <auto_retry_failed_tests>
                                     Automatically retry failed tests specified number of times to mitigate transient failures.
                                     Use with caution, it can hide real issues if used excessively.
                                     Results files (like HLKX, results.html, results.xml) contain information about test objects,
                                     so if a failed test is retried and passed on retry, it will be marked as passed in results files,
                                     without any indication that it was failed at the beginning. It is recommended to check logs for
                                     failed tests if this option is used.
                                     Possible values:
                                       -1 - retry indefinitely until all tests pass;
                                       0 - do not retry failed tests;
                                       N - retry failed tests up to N times.
        --query <query>              Run a query and exit without starting a test session.
                                     Supported queries: images-names
        --query-output-file <path>   Write query output to the specified file in addition to the log
        --session <path>             Bring up a previous test session from its workspace path
        --latest-session             Bring up the most recent test session
    -h, --help                       Show this message
Usage: auto_hck.rb install [install options]

        --debug                      Enable debug mode
    -p, --platform <platform_name>   Install VM for specified platform
    -f, --force                      Install all VM, replace studio if exist
        --skip_client                Skip client images installation
    -d, --drivers <drivers_list>     List of driver attach in install
        --driver-path <driver_path>  Path to the location of the driver wanted to be installed
        --no-reboot-after-bugcheck   Keep system in crashed state after crash for debugging (disables automatic reboot)
    -h, --help                       Show this message
```

### Selective CI (`triggers_check`)

`--diff` and `--triggers` are **not** on `bin/auto_hck test`. Use the standalone helper to decide whether CI should run tests:

```bash
bin/triggers_check --diff /path/to/diff.txt --triggers /path/to/triggers.yml
```

Exit code `0` means at least one trigger matched (run tests); exit code `1` means skip tests.

```text
Usage: triggers_check [--help] <options>

        --debug                      Printing debug information (optional)
        --diff <diff_file>           Path to text file containing a list of changed source files
        --triggers <trigger_file>    Path to text file containing a list of triggers
        --trigger_keys <trigger_keys>
                                     List of trigger keys
    -h, --help                       Show this message
```

### Dump mode

In dump mode, AutoHCK generates bash script files for each VM with all preparation steps. You can edit these files, update the QEMU command line, and then run it.

### Manual mode

In manual mode (`--manual`), AutoHCK performs the following steps:

- Run VMs
- Configure HLK environment (if driver binary present)
- Run selected tests (if driver binary present)
- Stop automatic test runs and start waiting for a manual exit
- Stop VMs and save all run logs

### Examples

```bash
bin/auto_hck install -p Win11_25H2x64
bin/auto_hck install -p Win2019x64 --force
bin/auto_hck test -d Balloon -p Win10_2004x86_bios --driver-path /path/to/driver
bin/auto_hck test -d NetKVM -p Win10_2004x64 --driver-path /path/to/driver -c ec3da560827922e5a82486cf19cd9c27e95455a9
bin/auto_hck test --svvp -p Win10_2004x64 --driver-path /path/to/virtio-drv
bin/auto_hck test -d NetKVM -p Win10_2004x64 --driver-path /path/to/driver --manual
bin/auto_hck test -d NetKVM -p Win10_2004x64 --manual
bin/auto_hck test --latest-session
bin/triggers_check --diff /path/to/diff.txt --triggers /path/to/triggers.yml
```

### Workspace

When starting AutoHCK a session workspace will be created inside the workspace directory configured in `config.json` at the path:
  + in test mode: `workspace/[engine-type]/[devices-list]-[platform]/[timestamp]/`
  + in test svvp mode: `workspace/[engine-type]/svvp-[platform]/[timestamp]/`
  + in install mode: `workspace/[engine-type]/[platform]/[timestamp]/`

A `latest` symlink under `workspace/` points at the most recent session directory.

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
