# typed: true

# DO NOT EDIT MANUALLY
# This is an autogenerated file for types exported from the `rtoolsHCK` gem.
# Please instead update this file by running `bin/tapioca gem rtoolsHCK`.


# ether class
#
# source://rtoolsHCK//lib/ether.rb#10
class Ether
  # @return [Ether] a new instance of Ether
  #
  # source://rtoolsHCK//lib/ether.rb#11
  def initialize(init_opts); end

  # source://rtoolsHCK//lib/ether.rb#142
  def close; end

  # source://rtoolsHCK//lib/ether.rb#154
  def cmd(cmd, timeout = T.unsafe(nil)); end

  private

  # source://rtoolsHCK//lib/ether.rb#95
  def connect; end

  # source://rtoolsHCK//lib/ether.rb#119
  def fetch(length); end

  # source://rtoolsHCK//lib/ether.rb#104
  def fetch_output_with_timeout(timeout); end

  # source://rtoolsHCK//lib/ether.rb#173
  def flush; end

  # source://rtoolsHCK//lib/ether.rb#26
  def get_exception_stack(exception); end

  # source://rtoolsHCK//lib/ether.rb#76
  def load_ether; end

  # source://rtoolsHCK//lib/ether.rb#48
  def load_instance_variables(init_opts); end

  # source://rtoolsHCK//lib/ether.rb#70
  def load_server; end

  # source://rtoolsHCK//lib/ether.rb#31
  def log_exception(exception, level); end

  # source://rtoolsHCK//lib/ether.rb#43
  def logger(level, progname = T.unsafe(nil), &_arg2); end

  # source://rtoolsHCK//lib/ether.rb#58
  def server_init_opts; end

  # source://rtoolsHCK//lib/ether.rb#130
  def unload_server; end

  # source://rtoolsHCK//lib/ether.rb#83
  def wait_for_client_acceptance; end
end

# ether buffer size
#
# source://rtoolsHCK//lib/ether.rb#117
Ether::ETHER_BUFFER_SIZE = T.let(T.unsafe(nil), Integer)

# ether exit timeout
#
# source://rtoolsHCK//lib/ether.rb#138
Ether::ETHER_EXIT_TIMEOUT = T.let(T.unsafe(nil), Integer)

# A custom Ether error exception
#
# source://rtoolsHCK//lib/exceptions.rb#28
class EtherError < ::RToolsHCKConnectionError; end

# rtoolsHCK version extend to class
#
# source://rtoolsHCK//lib/rtoolsHCK.rb#67
class RToolsHCK
  # == Description
  #
  # Initializes new object of type RToolsHCK to be used by establishing a
  # Telnet and a Tftp connection with the guest machine.
  #
  # == Params:
  #
  # +init_opts+::    Hash that has various initialize options to configure upon
  #                  initializing a RtoolsHCK object:
  #   :addr          - Controller machine's IP address
  #                    (default: 127.0.0.1)
  #   :user          - The user name to use in order to connect via winrm to the
  #                    guest
  #                    (default: Administrator)
  #   :pass          - The password of the user name specified
  #                    (default: PASSWORD)
  #   :port          - The port to be used for the connection
  #                    (default: 4000)
  #   :winrm_ports   - The clients winrm connection ports as a hash
  #                    (example: { 'Client' => port, ... })
  #                    (default: { 'Cl1' => 4001, 'Cl2' => 4002 }
  #   :json          - JSON format the output of the action methods
  #                    (default: true)
  #   :timeout       - The action's timeout in seconds
  #                    (default: 60)
  #   :log_to_stdout - Log to STDOUT switch
  #                    (default: false)
  #   :logger        - The ruby logger object for logging
  #                    (default: disabled)
  #   :outp_dir      - The path of the directory to fetch the output files to on
  #                    the local machine
  #                    (default: disabled)
  #   :r_script_file - The toolsHCK.ps1 file path on remote machine
  #                    (default: C:\\toolsHCK.ps1)
  #
  # @return [RToolsHCK] a new instance of RToolsHCK
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#140
  def initialize(init_opts); end

  # == Description
  #
  # Applies the filters on a project's test results.
  #
  # == Params:
  #
  # +project+::      The name of the project
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#814
  def apply_project_filters(project); end

  # == Description
  #
  # Applies the filters on a test result.
  #
  # == Params:
  #
  # +result+::       The index of the test result, use list_test_results action
  #                  to get it
  # +test+::         The id of the test, use list_tests action to get it
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#837
  def apply_test_result_filters(result, test, target, project, machine, pool); end

  # == Description
  #
  # Closes the instance.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1483
  def close; end

  # == Description
  #
  # Closes the instance and shuts down the studio.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1468
  def close_and_shutdown; end

  # == Description
  #
  # Boolean method to the instance being closed.
  #
  # @return [Boolean]
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1496
  def closed?; end

  # == Description
  #
  # Checks if connection is still alive.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1451
  def connection_check; end

  # == Description
  #
  # Creates a pool.
  #
  # == Params:
  #
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#420
  def create_pool(pool); end

  # == Description
  #
  # Creates a project.
  #
  # == Params:
  #
  # +project+::      The name of the project
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#537
  def create_project(project); end

  # == Description
  #
  # Creates a project's package and saves it to a file at <package> if used,
  # if not to %TEMP%\prometheus_packages\..., also fetches the package file to
  # the local machine if outp_dir param was used on initialization.
  #
  # == Params:
  #
  # +project+::      The name of the project
  # +playlist+::     Provide a playlist file path to apply, (can be nil)
  # +handler+::      The progress info handler, (can be nil), usage example:
  #                    handler = proc { |progress_package|
  #                      puts progress_package['stepscount']
  #                    }
  #                  progress_package is in JSON format and it has:
  #                  1. 'stepscount': a numeric progression steps count
  #                  1. 'steps': an array of 'stepscount' JSON entries that
  #                     each entry represents a single progression step's
  #                     progress info, each entry's content:
  #                     i. 'current': current progress counter value
  #                     i. 'maximum': maximum progress counter value
  #                     i. 'message': progress info message
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1040
  def create_project_package(project, playlist = T.unsafe(nil), handler = T.unsafe(nil)); end

  # == Description
  #
  # Creates a project's target.
  #
  # == Params:
  #
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#573
  def create_project_target(target, project, machine, pool); end

  # == Description
  #
  # Deletes a machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#491
  def delete_machine(machine, pool); end

  # == Description
  #
  # Delete the given path on the target machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +r_directory+::  The remote file/directory which should be deleted
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1224
  def delete_on_machine(machine, r_path); end

  # == Description
  #
  # Deletes a pool.
  #
  # == Params:
  #
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#436
  def delete_pool(pool); end

  # == Description
  #
  # Deletes a project.
  #
  # == Params:
  #
  # +project+::      The name of the project
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#553
  def delete_project(project); end

  # == Description
  #
  # Deletes a project's target.
  #
  # == Params:
  #
  # +target+::        The key of the target, use list_machine_targets to get it
  # +project+::       The name of the project
  # +machine+::       The name of the machine as registered with the HCK\HLK
  #                   controller
  # +pool+::          The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#596
  def delete_project_target(target, project, machine, pool); end

  # == Description
  #
  # Download file or directory from the machine to local directory.
  # BE CAREFUL! Download speed far less than upload one.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +r_directory+::  The remote file/directory which should be downloaded
  # +l_directory+::  The local file/directory path
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1192
  def download_from_machine(machine, r_path, l_path); end

  # == Description
  #
  # Checks to see if the given path exists on the target machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +r_directory+::  The remote file/directory which should be checked
  #
  # @return [Boolean]
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1208
  def exists_on_machine?(machine, r_path); end

  # == Description
  #
  # Gets a machine's ip address.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +ipv6+::         Get IPv6 address, :ipv6 to enable, disabled by default
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1064
  def get_machine_ip(machine, ipv6: T.unsafe(nil)); end

  # == Description
  #
  # Gets a machine's system information.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +output_format:: Specifies the format in which the output
  #                  is to be displayed.
  #                  Valid values: "TABLE", "LIST", "CSV".
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1085
  def get_machine_system_info(machine, output_format = T.unsafe(nil)); end

  # == Description
  #
  # Gets a project target's test info.
  #
  # == Params:
  #
  # +test+::         The id of the test, use list_tests action to get it
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#725
  def get_test_info(test, target, project, machine, pool); end

  # == Description
  #
  # Installs a driver package, (.inf file), on a machine.
  #
  # == Params:
  #
  # +machine+::             The name of the machine
  # +install_method+::      The method for driver installation
  # +l_directory+::         The local directory which has the driver package,
  #                         (.inf file)
  # +inf_file+::            The .inf file name
  #
  # == Optional params (symbols):
  #
  # +custom_cmd+::          The custom command for driver installation (optional)
  # +force_install_cert+::  Install certificate independently of driver installation
  #                         method (optional)
  # +sys_file+::            The .sys file name for export certificate (optional)
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1377
  def install_machine_driver_package(machine, install_method, l_directory, inf_file, options = T.unsafe(nil)); end

  # Returns the value of attribute json.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#398
  def json; end

  # Sets the attribute json
  #
  # @param value the value to set the attribute json to.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#398
  def json=(_arg0); end

  # == Description
  #
  # Lists the target devices of a machine that are available to be tested.
  #
  # == Params:
  #
  # +machine+::      The name of the machine
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#508
  def list_machine_targets(machine, pool); end

  # == Description
  #
  # Lists the pools info.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#404
  def list_pools; end

  # == Description
  #
  # Lists the projects info.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#521
  def list_projects; end

  # == Description
  #
  # Lists a test's results info.
  #
  # == Params:
  #
  # +test_id+::      The id of the test, use list_tests action to get it
  #                  If id is nil, all tests results will be listed
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#867
  def list_test_results(test_id, target, project, machine, pool); end

  # == Description
  #
  # Lists a project target's tests.
  #
  # == Params:
  #
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  # +test_type+::    Assign to manual or auto, (can be nil)
  # +test_status+::  Assign to failed, inqueue, notrun, passed or running,
  #                  (can be nil)
  # +playlist+::     Provide a playlist file path to apply, (can be nil)
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#649
  def list_tests(target, project, machine, pool, test_type = T.unsafe(nil), test_status = T.unsafe(nil), playlist = T.unsafe(nil)); end

  # == Description
  #
  # Shuts down or restarts a machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +restart+::      Restarts the machine, :restart to enable, disabled by
  #                  default
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1120
  def machine_shutdown(machine, restart: T.unsafe(nil)); end

  # == Description
  #
  # Moves a machine from one pool to another.
  #
  # == Params:
  #
  # +machine+::      The name of the machine
  # +from+::         The name of the source pool
  # +to+::           The name of the destination pool
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#454
  def move_machine(machine, from, to); end

  # == Description
  #
  # Queues a test, use get_test_results action to get the results.
  # (if the test needs two machines to run use -sup flag)
  # (if the test needs the IPv6 address of the support machine use -IPv6 flag)
  #
  # == Params:
  #
  # +test+::         The id of the test, use list_tests action to get it
  # +target+::       The key of the target, use list_machine_targets to get it
  # +project+::      The name of the project
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +pool+::         The name of the pool
  # +sup+::          The name of the support machine as registered with the
  #                  HCK\HLK controller, (can be nil)
  # +parameters+::   Additional parameters in format '{ ParameterName1: Value1, ParameterName2: Value2 }', (can be nil)
  # +ipv6+::         The IPv6 address of the support machine, (can be nil)
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#755
  def queue_test(test, target, project, machine, pool, sup = T.unsafe(nil), parameters = T.unsafe(nil), ipv6 = T.unsafe(nil)); end

  # == Description
  #
  # Tries to regain the connection to the guest machine using the given
  # credentials and addresses on initialization.
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1400
  def reconnect; end

  # == Description
  #
  # Run command on a machine, (powershell).
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +cmd+::          The command to run as a string
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1139
  def run_on_machine(machine, cmd); end

  # == Description
  #
  # Run command on a studio, (powershell).
  #
  # == Params:
  #
  # +command+::          The command to run as a string
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1155
  def run_on_studio(command); end

  # == Description
  #
  # Sets the state of a machine to Ready or NotReady.
  #
  # == Params:
  #
  # +machine+::      The name of the machine
  # +pool+::         The name of the pool
  # +state+::        The state, Ready or NotReady
  # +timeout+::      The action's timeout in seconds, 60 by deafult
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#473
  def set_machine_state(machine, pool, state, timeout = T.unsafe(nil)); end

  # == Description
  #
  # Shuts down or restarts the studio, (you will need to reconnect after this).
  #
  # == Params:
  #
  # +restart+::      Restarts the machine, :restart to enable, disabled by
  #                  default
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1100
  def shutdown(restart: T.unsafe(nil)); end

  # == Description
  #
  # Starts HLK related services at the machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#210
  def start_client_services(machine); end

  # == Description
  #
  # Updates the HCK\HLK controller's filters by giving a local .sql filter file.
  #
  # == Params:
  #
  # +l_filters+::    The local filter .sql file path
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#798
  def update_filters(l_filter); end

  # == Description
  #
  # Upload directory to temp directory of the machine.
  #
  # == Params:
  #
  # +machine+::      The name of the machine as registered with the HCK\HLK
  #                  controller
  # +l_directory+::  The local file/directory which should be uploaded
  # +r_directory+::  The remote file/directory
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1174
  def upload_to_machine(machine, l_directory, r_directory = T.unsafe(nil)); end

  # == Description
  #
  # Zips a test result's logs to a zip file fetches it to the local machine if
  # logs_dir param was used on initialization.
  #
  # == Params:
  #
  # +result_index+::         If index_instance_id is false the index of the test result,
  #                          use list_test_results action to get it
  #                          If index_instance_id is true the instance id of the test result
  # +test+::                 The id of the test, use list_tests action to get it
  # +target+::               The key of the target, use list_machine_targets to get it
  # +project+::              The name of the project
  # +machine+::              The name of the machine as registered with the HCK\HLK
  #                          controller
  # +pool+::                 The name of the pool
  # +index_instance_id+::    If true, the result_index is treated as an instance id
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#902
  def zip_test_result_logs(result_index:, test:, target:, project:, machine:, pool:, index_instance_id: T.unsafe(nil)); end

  private

  # source://rtoolsHCK//lib/rtoolsHCK.rb#375
  def action_exception_handler(exception); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1434
  def check_connection; end

  # @raise [WinrmPSRunError.new(where)]
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#273
  def check_run_output(run_output, where, cmd); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1264
  def do_delete_on_machine(machine, r_path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1245
  def do_download_from_machine(machine, r_path, l_path); end

  # @return [Boolean]
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#1256
  def do_exists_on_machine?(machine, r_path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#218
  def do_initialize(init_opts); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1342
  def do_install_machine_driver_package(machine, install_method, l_directory, inf_file, options); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#623
  def do_list_tests(cmd_line, l_playlist); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#778
  def do_upload_and_update_filter(l_filter); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#610
  def do_upload_playlist_file(l_playlist); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1233
  def do_upload_to_machine(machine, l_directory, r_directory = T.unsafe(nil)); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#985
  def dummy_package_progress_info_handler; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1272
  def export_certificate_script(sys_path, cer_path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#668
  def file_to_outp_dir(r_file_path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1304
  def get_custom_command(r_directory, windows_path, custom_cmd); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#81
  def get_exception_stack(exception); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#339
  def guest_basename(path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#343
  def guest_dirname(path); end

  # @raise [RToolsHCKError.new('action')]
  #
  # source://rtoolsHCK//lib/rtoolsHCK.rb#385
  def handle_action_exceptions(action, &block); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1003
  def handle_create_project_package(cmd_line, handler); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#74
  def handle_exceptions; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#957
  def handle_project_package(ret_str); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#925
  def handle_project_package_json(project_package); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#947
  def handle_project_package_normal(project_package, stream); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#349
  def handle_return(stream); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#701
  def handle_test_results(test_results, stream); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#676
  def handle_test_results_json(test_results); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#687
  def handle_test_results_normal(test_results, stream); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1325
  def install_certificate(machine, windows_path, sys_file = T.unsafe(nil)); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1283
  def install_certificate_script(cer_path); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1313
  def install_driver_command(r_directory, windows_path, install_method, custom_cmd = T.unsafe(nil)); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#241
  def load_instance_variables(init_opts); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#229
  def load_outp_dir(outp_dir); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#321
  def load_toolshck; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#308
  def load_winrm_fs; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#264
  def load_winrm_ps; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#369
  def log_action_call(action, binding); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#86
  def log_exception(exception, level); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#98
  def logger(level, progname = T.unsafe(nil), &_arg2); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#290
  def machine_connection(machine); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#296
  def machine_run(machine, cmd); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#980
  def package_progress_info_factory(progress_steps); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#990
  def package_progression_first_step(cmd_line, handler); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#996
  def package_progression_last_step(current, handler); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#970
  def package_progression_loop(current, maximum, handler); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#358
  def parse_action_parameters(action, binding); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#937
  def parse_project_package_guest_path(stream); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1411
  def priv_close; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1290
  def replace_command(cmd, replacement_list); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#282
  def run(cmd); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#197
  def start_client_service(machine, service_name); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#179
  def start_studio_service(service_name); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#191
  def start_studio_services; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#325
  def toolshck_ether_init_opts; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1424
  def unload_ether; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1430
  def unload_toolshck; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#1416
  def unload_winrm_ps; end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#169
  def validate_init_opts(init_opts); end

  # source://rtoolsHCK//lib/rtoolsHCK.rb#252
  def winrm_options_factory(addr, port, user, pass); end
end

# init_opts initialization defaults
#
# source://rtoolsHCK//lib/rtoolsHCK.rb#155
RToolsHCK::INIT_OPTS_DEFAULTS = T.let(T.unsafe(nil), Hash)

# Progression rate divider, used for the synchronization with the controller
#
# source://rtoolsHCK//lib/rtoolsHCK.rb#1013
RToolsHCK::PROGRESSION_RATE_DIVIDER = T.let(T.unsafe(nil), Integer)

# toolsHCK connection timeout in seconds
#
# source://rtoolsHCK//lib/rtoolsHCK.rb#319
RToolsHCK::TOOLSHCK_CONNECTION_TIMEOUT = T.let(T.unsafe(nil), Integer)

# source://rtoolsHCK//lib/rtoolsHCK.rb#68
RToolsHCK::WINRM_OPERATION_TIMEOUT = T.let(T.unsafe(nil), Integer)

# source://rtoolsHCK//lib/rtoolsHCK.rb#69
RToolsHCK::WINRM_RECIEVE_TIMEOUT = T.let(T.unsafe(nil), Integer)

# source://rtoolsHCK//lib/rtoolsHCK.rb#70
RToolsHCK::WINRM_RETRY_INTERVAL = T.let(T.unsafe(nil), Integer)

# A custom RToolsHCK action error exception
#
# source://rtoolsHCK//lib/exceptions.rb#19
class RToolsHCKActionError < ::RToolsHCKError; end

# A custom RToolsHCK connection error exception
#
# source://rtoolsHCK//lib/exceptions.rb#16
class RToolsHCKConnectionError < ::RToolsHCKError; end

# A custom RToolsHCK error exception
#
# source://rtoolsHCK//lib/exceptions.rb#4
class RToolsHCKError < ::StandardError
  # Initialization of the custom exception
  #
  # @return [RToolsHCKError] a new instance of RToolsHCKError
  #
  # source://rtoolsHCK//lib/exceptions.rb#9
  def initialize(where); end

  # Custom addition to the exception backtrace, (better logging)
  #
  # source://rtoolsHCK//lib/exceptions.rb#6
  def where; end
end

# server class
#
# source://rtoolsHCK//lib/server.rb#8
class Server
  # @return [Server] a new instance of Server
  #
  # source://rtoolsHCK//lib/server.rb#9
  def initialize(init_opts); end

  # source://rtoolsHCK//lib/server.rb#93
  def close; end

  # source://rtoolsHCK//lib/server.rb#17
  def run_server; end

  private

  # source://rtoolsHCK//lib/server.rb#44
  def check_script_file; end

  # source://rtoolsHCK//lib/server.rb#54
  def deploy_script_file; end

  # source://rtoolsHCK//lib/server.rb#87
  def guest_basename(path); end

  # source://rtoolsHCK//lib/server.rb#36
  def load_instance_variables(init_opts); end

  # source://rtoolsHCK//lib/server.rb#62
  def load_toolshck_server; end

  # source://rtoolsHCK//lib/server.rb#31
  def logger(level, progname = T.unsafe(nil), &_arg2); end

  # source://rtoolsHCK//lib/server.rb#81
  def process_script; end
end

# A custom Server error exception
#
# source://rtoolsHCK//lib/exceptions.rb#25
class ServerError < ::RToolsHCKConnectionError; end

# A custom Winrm powershell run error exception
#
# source://rtoolsHCK//lib/exceptions.rb#22
class WinrmPSRunError < ::RToolsHCKActionError; end
