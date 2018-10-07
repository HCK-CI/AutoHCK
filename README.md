# AutoHCK

[![CircleCI](https://circleci.com/gh/daynix/AutoHCK2.svg?style=svg)](https://circleci.com/gh/daynix/AutoHCK2)

AutoHCK is a tool for automating HCK/HLK testing, doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what os.

## Getting Started

There are not so few steps needed to install and set up AutoHCK, First of all clone AutoHCK and follow the instruction below:

### QEMU
Use your package manager to install QEMU or build it from [source](https://github.com/qemu/qemu)

### VirtHCK
Clone [VirtHCK](https://github.com/daynix/VirtHCK), AutoHCK will use it as a dependency.

### toolsHCK
Get a copy of the powershell script file in [rtoolsHCK](https://github.com/HCK-CI/toolsHCK)

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

### Images preperation
This is similar to making regular HLK/HCK studio and clients images with with few additionals configurations, detailed instrutions available at [HLK-Setup-Scripts](https://github.com/HCK-CI/HLK-Setup-Scripts)

### Dropbox integration
AutoHCK allows integration with Dropbox, automatically uploading results and logs to specific location.
to do that you will need to create auth2 token
1. go to https://www.dropbox.com/developers/apps and click on 'Create app'
2. select 'Dropbox API', 'Full Dropbox' access type and give it a unique name.
3. click on 'Generated access token' and copy the token to config.json file.

### Github integration
When specifing a pull request AutoHCK can mark test results on github and link to dropbox logs folder.
to do that you will need to create a personal access token.
1. go to https://github.com/settings/tokens and click on 'Generate new token'
2. give it a name, select: repo:status and click 'Generate token'
3. update your GitHub credendials in the `config.json` file, username and the generated token as password.

### Configuration
There are 3 diffrenet JSON files for configurations, examples included in the files:
* `config.json` is the general configuration file which holds the paths to the dependencies stated above.
* `platforms.json` list of configured opertaions systems images.
* `devices.json` list of devices drivers information for testing

## Usage

Once everything is installed and configured, run `./bin/auto_hck` with these parameters:
```
Required:
-t, --tag [PROJECT]-[OS][ARCH]   The driver name and architecture
-p, --path [PATH-TO-DRIVER]      The location of the driver
Optional:
-d, --diff <DIFF-LIST-FILE>      Path to text file containing a list of changed source files
-c, --commit <COMMIT-HASH>       Commit hash for updating github status
-D, --debug                      Printing debug information
```
### Examples
```
ruby ./bin/auto_hck -t Balloon-Win10x86 -p /home/hck-ci/balloon/win10/x86
ruby ./bin/auto_hck -t NetKVM-Win10x64 -p /home/hck-ci/workspace -d /path/to/diff.txt
ruby ./bin/auto_hck -t viostor-Win10x64 -p /home/hck-ci/viostor -d /path/to/diff.txt -c ec3da560827922e5a82486cf19cd9c27e95455a9
```
### Workspace
When starting AutoHCK session a workspace will be created inside the workspace directory configured in `config.json` at the path: `workspace/[device-short]/[platform]/[timestamp]/`
Inside AutoHCK will save the following files:
* qcow2 snapshots of the backing setup images
* AutoHCK log file
* Executables: `st.sh` `c1.sh` `c2.sh` to rerun test setup machines manually.
* HLKX/HCKX file after tests session ended.

## Author

* **Lior Haim** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)


