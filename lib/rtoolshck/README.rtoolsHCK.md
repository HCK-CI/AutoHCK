
# rtoolsHCK

rtoolsHCK is a ruby gem tool-kit based on toolsHCK for managing and maintaining the HCK setup remotely.

## Getting Started

Follow these instructions to install and start using rtoolsHCK.

### Prerequisites

What things you need to install the gem

* [winrm](https://github.com/WinRb/WinRM)
* [winrm-fs](https://github.com/WinRb/winrm-fs)

## Usage

### Initialization options

A hash that contains:

| Parameter | Descriptions |
| --------- | ------------ |
| :addr | Controller machine's IP address<br>**(default: 127.0.0.1)**
| :user | The user name to use in order to connect via winrm to the guest<br>**(default: Administrator)**
| :pass | The password of the user name specified<br>**(default: PASSWORD)**
| :clients_addrs | The clients winrm connection ports as a hash<br>(example: { 'Client' => { addr: '192.168.0.18', port: 4001 }, ... })<br>**(default: { 'CL1' => { addr: '192.168.100.2' }, 'CL2' => { addr: '192.168.100.3' } })**
| :json | JSON format the output of the action methods<br>**(default: true)**
| :timeout | The action's timeout in seconds<br>**(default: 60)**
| :log_to_stdout | Log to STDOUT switch<br>**(default: false)**
| :logger | The ruby logger object for logging<br>**(default: disabled)**
| :outp_dir | The path of the directory to fetch the output files to on the local machine<br>**(default: disbaled)**

### Examples

#### Creating a rtoolsHCK session to create a new "test" pool and list the pools info
```
require 'rtoolsHCK'

logger = Logger.new('./logger.log')

init_opts = {
  addr: '10.0.1.5',
  user: 'Administrator',
  pass: 'PASSWORD',
  winrm_ports: { 'Cl1' => 4001, 'Cl2' => 4002 },
  logger: logger,
  log_to_stdout: true,
  outp_dir: './fethced_files'
}

rtoolsHCK_session = AutoHCK::RToolsHCK::new(init_opts)

rtoolsHCK_session.create_pool('test')
rtoolsHCK_session.list_pools

rtoolsHCK_session.close
```

#### Creating a rtoolsHCK session to shutdown the two clients and the controller's machines
```
require 'rtoolsHCK'

logger = Logger.new('./logger.log')

init_opts = {
  addr: '10.0.1.5',
  user: 'Administrator',
  pass: 'PASSWORD',
  winrm_ports: { 'Cl1' => 4001, 'Cl2' => 4002 },
  logger: logger,
  log_to_stdout: true,
  outp_dir: './fethced_files'
}

rtoolsHCK_session = AutoHCK::RToolsHCK::new(init_opts)

rtoolsHCK_session.machine_shutdown('cl1-win10x64')
rtoolsHCK_session.machine_shutdown('cl2-win10x64')
rtoolsHCK_session.close_and_shutdown
```

### Methods

#### Action methods

| Action | Descriptions |
| ------ | ------------ |
| **list_pools** | Lists the pools info. |
| **create_pool** | Creates a pool. |
| **delete_pool** | Deletes a pool. |
| **move_machine** | Moves a machine from one pool to another. |
| **set_machine_state** | Sets the state of a machine to Ready or NotReady. |
| **delete_machine** | Deletes a machine. |
| **list_machine_targets** | Lists the target devices of a machine that are available to be tested. |
| **list_projects** | Lists the projects info. |
| **create_project** | Creates a project. |
| **delete_project** | Deletes a project. |
| **create_project_target** | Creates a project's target. |
| **delete_project_target** | Deletes a project's target. |
| **list_tests** | Lists a project target's tests. |
| **get_test_info** | Gets a project target's test info. |
| **queue_test** | Queue's a test, use get_test_results to get the results. |
| **update_filters** | Updates the HCK\HLK controller's filters. |
| **apply_project_filters** | Applies the filters on a project's test results. |
| **apply_test_result_filters** | Applies the filters on a test result. |
| **list_test_results** | Lists a test results info. |
| **zip_test_result_logs** | Zipps a test result's log and fetches the zip. |
| **create_project_package** | Creates a project's package. |

#### Control methods

| Action | Descriptions |
| ------ | ------------ |
| **get_machine_ip** | Gets a machine's ip address. |
| **shutdown** | Shuts down or restarts the studio. |
| **machine_shutdown** | Shuts down or restarts a client machine. |
| **install_machine_driver_package** | Installs a driver package on a client machine. |
| **reconnect** | Tries to regain the connection to the guest machine. |
| **connection_check** | Checks if connection is still alive. |
| **close_and_shutdown** | Closes the instance and shuts down the studio. |
| **close** | Closes the instance. |
| **closed?** | Boolean methods to the instance being closed. |

For more info execute this command in the git clone's directory
```
rake rdoc
```
And open doc/index.html with a browser.

## Authors

* **Bishara AbuHattoum**
