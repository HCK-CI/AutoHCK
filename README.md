# AutoHCK

[![CircleCI](https://circleci.com/gh/HCK-CI/AutoHCK.svg?style=svg)](https://circleci.com/gh/HCK-CI/AutoHCK)

AutoHCK is a tool for automating HCK/HLK testing, doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

## Getting Started

There are not so few steps needed to install and set up AutoHCK, First of all clone AutoHCK and follow the instruction below:

### QEMU
Use your package manager to install QEMU or build it from [source](https://github.com/qemu/qemu)

### VirtHCK
Clone [VirtHCK](https://github.com/daynix/VirtHCK), AutoHCK will use it as a dependency.

### HLK setup scripts
Clone [HLK-Setup-Scripts](https://github.com/HCK-CI/HLK-Setup-Scripts), AutoHCK will use it as a dependency for image creation.

### toolsHCK
Get a copy of the powershell script file in [toolsHCK](https://github.com/HCK-CI/toolsHCK)

### rtoolsHCK
Get a clone of [rtoolsHCK](https://github.com/HCK-CI/rtoolsHCK), execute the follwing to build and install as a gem:
```
rake build
rake install
```

### RubyGems
Install the following gems using bundler with `bundler install` or `gem install <gem_name>`:
* [dropbox_api](https://rubygems.org/gems/dropbox_api)
* [faraday](https://rubygems.org/gems/faraday) (version 0.12.2)
* [net-ping](https://rubygems.org/gems/net-ping)
* [filelock](https://rubygems.org/gems/filelock)
* [octokit](https://rubygems.org/gems/octokit)
* [mono_logger](https://rubygems.org/gems/mono_logger)
* [sqlite3](https://rubygems.org/gems/sqlite3)

### DHCP SERVER
In order to connect to the Studio machine in each HLK/HCK setup, we need to set up a DHCP server that will provide each studio with a predefined unique IP address. The server will assign the IP address according to the machine network adapter mac address with the following rule:
```
56:00:XX:00:XX:dd > 192.168.0.XX
```
Use the following script [OpenDHCPServerSetup](https://github.com/HCK-CI/OpenDHCPServerSetup) to install and configure OpenDHCPServer.

### Microsoft HCK filters
Filters are fixes for problematic tests, read more at: [Microsoft HLK Filters](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/user/windows-hardware-lab-kit-filters)
To run tests with applied filters automatically, get a copy of `UpdateFilters.sql` from [HCK-CI/hckfilters](https://github.com/HCK-CI/hckfilters) and place them inside AutoHCK at `filters/UpdateFilters.sql`.

### Microsoft HLK playlists
To run HLK tests with latest Microsoft compatibility playlist clone [HLK Playlists](https://github.com/HCK-CI/hlkplaylists) inside AutoHCK and rename the directory to playlists, once it's there AutoHCK will look for the right xml playlist file and apply it to the tests.

### Sudoer with no password
To run AutoHCK correctly the runnig user should have permission to run sudo commands without prompting his password, do this by adding the following line to sudoers file /etc/sudoers
__This might be dangerous to your computer security, do this at your own risk__
```
hck-ci ALL=(ALL) NOPASSWD:ALL
```

### Images installation
See [ImageInstallation.md](ImageInstallation.md) for more details

### Result uploading
AutoHCK supports uploading the results of the tests, (logs, test results and the hckx\hlkx package file), using the supported uploaders by configuring the array field "result_uploader" in the `config.json` file to the desired uploaders for AutoHCK to use, for example, to use dropbox:
```
    "studio_username": "Administrator",
    "studio_password": "Qum5net.",
 -> "result_uploaders": [ "dropbox" ]
}
```
#### Supported result uploaders
##### 1. Dropbox
To use dropbox result uploading capabilities you will need to create auth2 token
1. go to https://www.dropbox.com/developers/apps and click on 'Create app'
2. select 'Dropbox API', 'Full Dropbox' access type and give it a unique name.
3. click on 'Generated access token' and use it as environment variable with `export AUTOHCK_DROPBOX_TOKEN=<TOKEN>`
##### 2. (Other result uploaders are in working progress)

### Github integration
When specifing a pull request AutoHCK can mark test results on github and link to dropbox logs folder.
to do that you will need to create a personal access token.
1. go to https://github.com/settings/tokens and click on 'Generate new token'
2. give it a name, select: repo:status and click 'Generate token'
3. set new environment variable for your username and token with `export AUTOHCK_GITHUB_LOGIN=<LOGIN>` and `export AUTOHCK_GITHUB_TOKEN=<TOKEN>`

### Configuration
There are 6 diffrenet JSON files for configurations, examples included in the files:
* `config.json` is the general configuration file which holds the paths to the dependencies stated above.
* `platforms.json` list of configured opertaions systems images. #TODO: Fix
* `devices.json` list of devices drivers information for testing.
* `iso.json` list of ISO with information for unattended VM installation.
* `hckinstall.json` is the specific configuration file for install engine.
* `kit.json` list of HCK/HLK kits.

### Utils
#### Cleanup
This script deletes logs and snapshots from HCK runs that are more than 1 month old, the script can be run as a cronjob in order to prevent autoHCK from filling the disk on the system.

## Usage

Once everything is installed and configured, run `./bin/auto_hck` with these parameters:
```
Usage: auto_hck.rb [common options] <command> [command options]

        --debug                      Printing debug information
    -v, --version                    Display version information and exit
    -h, --help                       Show this message
Usage: auto_hck.rb test [test options]

    -p, --platform <platform_name>   Platform for run test
    -d, --drivers <drivers_list>     List of driver for run test
        --driver-path <driver_path>  Path to the location of the driver wanted to be tested
    -c, --commit <commit_hash>       Commit hash for CI status update
        --diff <diff_file>           Path to text file containing a list of changed source files
    -h, --help                       Show this message
Usage: auto_hck.rb install [install options]

    -p, --platform <platform_name>   Install VM for specified platform
    -f, --force                      Install all VM, replace studio if exist
    -h, --help                       Show this message
```
### Examples
```
ruby ./bin/auto_hck test --drivers Balloon --platform Win10x86 --driver-path /home/hck-ci/balloon/win10/x86
ruby ./bin/auto_hck test --drivers NetKVM --platform Win10x64 --driver-path /home/hck-ci/workspace --diff /path/to/diff.txt
ruby ./bin/auto_hck test --drivers viostor --platform Win10x64 --driver-path /home/hck-ci/viostor --diff /path/to/diff.txt -c ec3da560827922e5a82486cf19cd9c27e95455a9
ruby ./bin/auto_hck install --platform Win2019x64 --force
```
### Workspace
When starting AutoHCK a session workspace will be created inside the workspace directory configured in `config.json` at the path:
  - in test mode: `workspace/[engine-type]/[setup-manager]/[device-short]/[platform]/[timestamp]/`
  - in install mode: `workspace/[engine-type]/[setup-manager]/[platform]/[timestamp]/`

Inside AutoHCK will save the following files:
* qcow2 snapshots of the backing setup images: `[filename]-snapshot.qcow2`
* AutoHCK log file: `[device-short]-[platform].log`
* archived tests log files: `[timestamp]-[testid].zip`
* Executables: `st.sh` `c1.sh` `c2.sh` to rerun test setup machines manually.
* HLKX/HCKX file (after tests session ended): `[device-short]-[platform].hlkx`

## Authors

* **Lior Haim** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Bishara AbuHattoum** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Basil Salman** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
