# frozen_string_literal: true

require_relative 'exceptions'
require_relative 'ether'

# rubocop:disable Metrics/ClassLength, Metrics/ParameterLists

# == Description
#
# A ruby class the resembles tool set for HCK\HLK with various purposes which
# covers several actions as explained in the list if actions below.
#
# == Actions list
#
# +list_pools+::                 Lists the pools info.
#
# +create_pool+::                Creates a pool.
#
# +delete_pool+::                Deletes a pool.
#
# +move_machine+::               Moves a machine from one pool to another.
#
# +set_machine_state+::          Sets the state of a machine to Ready or
#                                NotReady.
#
# +delete_machine+::             Deletes a machine
#
# +list_machine_targets+::       Lists the target devices of a machine that are
#                                available to be tested.
#
# +list_projects+::              Lists the projects info.
#
# +create_project+::             Creates a project.
#
# +delete_project+::             Deletes a project.
#
# +create_project_target+::      Creates a project's target.
#
# +delete_project_target+::      Deletes a project's target.
#
# +list_tests+::                 Lists a project target's tests.
#
# +get_test_info+::              Gets a project target's test info.
#
# +queue_test+::                 Queue's a test, use get_test_results to get the
#                                results.
#
# +update_filters+::             Updates the HCK\HLK controller's filters.
#
# +apply_project_filters+::      Applies the filters on a project's test
#                                results.
#
# +apply_test_result_filters+::  Applies the filters on a test result.
#
# +list_test_results+::          Lists a test results info.
#
# +zip_test_result_logs+::       Zipps a test result's log and fetches the zip.
#
# +create_project_package+::     Creates a project's package.
module AutoHCK
  class RToolsHCK
    WINRM_OPERATION_TIMEOUT = 9_999
    WINRM_RECIEVE_TIMEOUT = 99_999
    WINRM_RETRY_INTERVAL = 60
    WINRM_DEFAULT_PORT = 5985
    ETHER_DEFAULT_PORT = 4000

    # Progression rate divider, used for the synchronization with the controller
    PROGRESSION_RATE_DIVIDER = 30
    # toolsHCK connection timeout in seconds
    TOOLSHCK_CONNECTION_TIMEOUT = 60

    # Actions that can be performed in no_studio mode (client-only actions)
    CLIENT_ACTIONS = %i[
      start_client_services
      get_machine_system_info
      machine_shutdown
      run_on_machine
      upload_to_machine
      download_from_machine
      exists_on_machine?
      delete_on_machine
      install_machine_driver_package
      close
    ].freeze

    # init_opts initialization defaults
    INIT_OPTS_DEFAULTS = {
      addr: '192.168.100.1',
      port: WINRM_DEFAULT_PORT,
      ether_port: ETHER_DEFAULT_PORT,
      user: 'Administrator',
      pass: 'PASSWORD',
      clients_addrs: {
        'CL1' => { addr: '192.168.100.2', port: WINRM_DEFAULT_PORT },
        'CL2' => { addr: '192.168.100.3', port: WINRM_DEFAULT_PORT }
      },
      json: true,
      timeout: 60,
      logger: nil,
      log_to_stdout: false,
      outp_dir: nil,
      r_script_file: 'C:\\toolsHCK.ps1',
      no_studio: false
    }.freeze

    private

    def handle_exceptions
      yield
    rescue StandardError => e
      log_exception(e, 'error')
      raise e
    end

    def get_exception_stack(exception)
      exception.backtrace.select { |line| line.include?(File.dirname(__FILE__)) }
               .join("\n   -- ")
    end

    def log_exception(exception, level)
      eclass = exception.class
      emessage = exception.message
      estack = get_exception_stack(exception)
      if exception.is_a?(RToolsHCKError)
        ewhere = exception.where
        logger(level, ewhere) { "(#{eclass}) #{emessage}\n   -- #{estack}" }
      else
        logger(level, eclass) { "#{emessage}\n   -- #{estack}" }
      end
    end

    def logger(level, progname = nil, &)
      @stdout_logger.public_send(level, progname, &) if @log_to_stdout
      @logger&.public_send(level, progname, &)
    end

    public

    # == Description
    #
    # Initializes new object of type RToolsHCK to be used by establishing a
    # Telnet and a Tftp connection with the guest machine.
    #
    # == Params:
    #
    # +init_opts+::    Hash that has various initialize options to configure upon
    #                  initializing a RtoolsHCK object:
    #   :addr          - Controller/Studio machine's IP address
    #                    (default: 192.168.100.1)
    #                    (default is based on HLK-Setup-Script settings)
    #   :port          - The port to be used for the WinRM connection
    #                    (default: 5985)
    #   :ether_port    - The port to be used for the toolsHCK Ether connection
    #                    (default: 4000)
    #   :user          - The user name to use in order to connect via WinRM to the
    #                    guest
    #                    (default: Administrator)
    #   :pass          - The password of the user name specified
    #                    (default: PASSWORD)
    #   :clients_addrs - The clients WinRM connection ip and port (default: 5985) as a hash
    #                    (example: { 'Client' => { addr: '192.168.0.18', port: 4001 }, ... })
    #                    (default: { 'CL1' => { addr: '192.168.100.2' }, 'CL2' => { addr: '192.168.100.3' } })
    #                    (default is based on HLK-Setup-Script settings)
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
    def initialize(init_opts)
      init_opts = validate_init_opts(init_opts)

      @log_to_stdout = init_opts[:log_to_stdout]
      @stdout_logger = Logger.new($stdout) if @log_to_stdout
      @logger = init_opts[:logger]
      handle_exceptions { do_initialize(init_opts) }
    rescue StandardError
      priv_close
      raise
    end

    private

    def validate_init_opts(init_opts)
      extra_keys = (init_opts.keys - INIT_OPTS_DEFAULTS.keys)
      unless extra_keys.empty?
        if extra_keys.include?(:winrm_ports)
          raise RToolsHCKError.new('initialize'),
                'The :winrm_ports option is deprecated, use :clients_addrs instead.'
        end

        raise RToolsHCKError.new('initialize'),
              "Undefined initialization options: #{extra_keys.join(', ')}."
      end

      INIT_OPTS_DEFAULTS.merge(init_opts)
    end

    def start_studio_service(service_name)
      retries ||= 0
      run("Start-Service #{service_name}")
    rescue WinrmPSRunError => e
      raise e unless (retries += 1) < 4

      logger('warn', "#{e.message} Retrying in #{WINRM_RETRY_INTERVAL} seconds...")
      sleep(WINRM_RETRY_INTERVAL)

      retry
    end

    def start_studio_services
      services = %w[WTTServer HLKsvc DTMService WttChangeScheduler]
      services.each { |service_name| start_studio_service(service_name) }
      logger('info', 'HLK Services started successfully')
    end

    def start_client_service(machine, service_name)
      machine_run(machine, "Start-Service #{service_name}")
    end

    public

    # == Description
    #
    # Starts HLK related services at the machine.
    #
    # == Params:
    #
    # +machine+::      The name of the machine
    def start_client_services(machine)
      services = %w[HLKsvc]
      services.each { |service_name| start_client_service(machine, service_name) }
      logger('debug', "Machine #{machine}: HLK Services started successfully")
    end

    private

    def do_initialize(init_opts)
      load_outp_dir(init_opts[:outp_dir])
      load_instance_variables(init_opts)
      if @no_studio
        logger('debug', 'initialize') { "no-studio mode: clients=#{@clients_addrs.keys}" }
      else
        logger('debug', 'initialize') { "#{@user}:#{@pass}@#{@addr}" }
        load_winrm_ps
        load_winrm_fs
        start_studio_services
        load_toolshck
      end
      @closed = false
    end

    def load_outp_dir(outp_dir)
      @outp_dir = nil
      return if outp_dir.nil?

      unless File.directory?(outp_dir)
        raise RToolsHCKError.new('initialize/outp'),
              "can't find the directory outp_dir specefied."
      end
      @outp_dir = File.expand_path(outp_dir)
      logger('debug', 'initialize/outp') { "outp_dir assigned to #{@outp_dir}" }
    end

    def load_instance_variables(init_opts)
      @addr = init_opts[:addr]
      @user = init_opts[:user]
      @pass = init_opts[:pass]
      @port = init_opts[:port]
      @ether_port = init_opts[:ether_port]
      @clients_addrs = init_opts[:clients_addrs]
      @timeout = init_opts[:timeout]
      @json = init_opts[:json]
      @r_script_file = init_opts[:r_script_file]
      @no_studio = init_opts[:no_studio]
    end

    def winrm_options_factory(addr, port, user, pass)
      {
        endpoint: "http://#{addr}:#{port}/wsman",
        operation_timeout: WINRM_OPERATION_TIMEOUT,
        receive_timeout: WINRM_RECIEVE_TIMEOUT,
        transport: :plaintext,
        user:,
        password: pass,
        basic_auth_only: true
      }
    end

    def load_winrm_ps
      logger('debug', 'initialize/load_winrm_ps') { 'loading winrm shell...' }
      @connection_options = winrm_options_factory(@addr, @port || WINRM_DEFAULT_PORT, @user, @pass)
      @connection = WinRM::Connection.new(@connection_options)
      @winrm_ps = @connection.shell(:powershell)
      run('date')
      logger('info', 'initialize/load_winrm_ps') { 'winrm shell loaded!' }
    end

    def check_run_output(run_output, where, cmd)
      return if run_output.exitcode.zero?

      error = "Running '#{cmd}' failed with exit code #{run_output.exitcode}." \
              "#{"\n   -- stdout:\n#{run_output.stdout}" unless run_output.stdout.empty?}" \
              "#{"\n   -- stderr:\n#{run_output.stderr}" unless run_output.stderr.empty?}"
      raise WinrmPSRunError.new(where), error
    end

    def run(cmd)
      run_output = @winrm_ps.run(cmd)
      where = 'winrm/run'

      check_run_output(run_output, where, cmd)
      run_output.stdout
    end

    def machine_connection(machine)
      clients_addr = @clients_addrs[machine]
      if clients_addr.nil?
        raise RToolsHCKError.new('machine_connection'),
              "Unknown machine '#{machine}'. Available machines: #{@clients_addrs.keys.join(', ')}"
      end

      options = winrm_options_factory(
        clients_addr[:addr], clients_addr[:port] || WINRM_DEFAULT_PORT,
        @user, @pass
      )
      WinRM::Connection.new(options)
    end

    def machine_run(machine, cmd)
      where = "#{machine}/winrm/run"
      machine_connection(machine).shell(:powershell) do |ps_shell|
        run_output = ps_shell.run(cmd)

        check_run_output(run_output, where, cmd)
        run_output.stdout
      end
    rescue HTTPClient::KeepAliveDisconnected
      raise WinrmPSRunError.new(where), "Machine #{machine} reset connection."
    end

    def load_winrm_fs
      logger('debug', 'initialize/load_winrm_fs') do
        'creating winrm file manager instance'
      end
      @winrm_fs = WinRM::FS::FileManager.new(@connection)
      logger('info', 'initialize/load_winrm_fs') do
        'winrm file manager instance created!'
      end
    end

    def load_toolshck
      @toolshck_ether = Ether.new(toolshck_ether_init_opts)
    end

    def toolshck_ether_init_opts
      {
        winrm_connection_options: @connection_options,
        server_addr: @addr,
        server_port: @ether_port || ETHER_DEFAULT_PORT,
        operation_timeout: @timeout,
        connection_timeout: TOOLSHCK_CONNECTION_TIMEOUT,
        outp_dir: @outp_dir,
        r_script_file: @r_script_file,
        log_to_stdout: @log_to_stdout,
        logger: @logger
      }
    end

    def guest_basename(path)
      path&.split('\\')&.last
    end

    def guest_dirname(path)
      return nil if path.nil?

      path.split('\\').first(path.split('\\').size - 1).join('\\')
    end

    def handle_return(stream)
      if @json
        JSON.parse(stream)
      else
        puts(stream)
        !stream.include?('WARNING')
      end
    end

    def parse_action_parameters(action, binding)
      method(action).parameters.map do |param|
        param_str = "#{param[1]} "
        param_str + if param[0].equal?(:opt)
                      "is #{binding.local_variable_get(param[1]) ? 'on' : 'off'}"
                    else
                      "= #{binding.local_variable_get(param[1])}"
                    end
      end
    end

    def log_action_call(action, binding)
      action_parameters = parse_action_parameters(action, binding)
      action_parameters.push('no parameters') if action_parameters.empty?
      logger('debug', "action/#{action}") { action_parameters.join(', ') }
    end

    def action_exception_handler(exception)
      log_exception(exception, 'debug')
      if @json
        { 'result' => 'Failure', 'message' => exception.message }
      else
        puts "WARNING: #{exception.message}"
        false
      end
    end

    def handle_action_exceptions(action, &block)
      raise RToolsHCKError.new('action'), 'instance is closed.' if @closed
      if @no_studio && !CLIENT_ACTIONS.include?(action)
        raise RToolsHCKError.new(action.to_s), 'not supported in no_studio mode.'
      end

      log_action_call(action, block.binding)
      handle_exceptions do
        yield
      # We can have ECONNREFUSED error due to direct connection to
      # clients instead of proxy through studio
      # We can have EHOSTUNREACH error due to network issues or machine rebooting
      # Safety catch this exception, the action wrapper will retry if needed
      rescue RToolsHCKError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        action_exception_handler(e)
      end
    end

    public

    attr_accessor :json

    # == Description
    #
    # Lists the pools info.
    #
    def list_pools
      handle_action_exceptions(__method__) do
        cmd_line = ['listpools']
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Creates a pool.
    #
    # == Params:
    #
    # +pool+::         The name of the pool
    def create_pool(pool)
      handle_action_exceptions(__method__) do
        cmd_line = ["createpool '#{pool}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Deletes a pool.
    #
    # == Params:
    #
    # +pool+::         The name of the pool
    def delete_pool(pool)
      handle_action_exceptions(__method__) do
        cmd_line = ["deletepool '#{pool}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Moves a machine from one pool to another.
    #
    # == Params:
    #
    # +machine+::      The name of the machine
    # +from+::         The name of the source pool
    # +to+::           The name of the destination pool
    def move_machine(machine, from, to)
      handle_action_exceptions(__method__) do
        cmd_line = ["movemachine '#{machine}' '#{from}' '#{to}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def set_machine_state(machine, pool, state, timeout = @timeout)
      handle_action_exceptions(__method__) do
        cmd_line = ["setmachinestate '#{machine}' '#{pool}' '#{state}'"]
        cmd_line << "-timeout #{timeout}"
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' '), timeout))
      end
    end

    # == Description
    #
    # Deletes a machine.
    #
    # == Params:
    #
    # +machine+::      The name of the machine
    # +pool+::         The name of the pool
    def delete_machine(machine, pool)
      handle_action_exceptions(__method__) do
        cmd_line = ["deletemachine '#{machine}' '#{pool}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Lists the target devices of a machine that are available to be tested.
    #
    # == Params:
    #
    # +machine+::      The name of the machine
    # +pool+::         The name of the pool
    def list_machine_targets(machine, pool)
      handle_action_exceptions(__method__) do
        cmd_line = ["listmachinetargets '#{machine}' '#{pool}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Lists the projects info.
    #
    def list_projects
      handle_action_exceptions(__method__) do
        cmd_line = ['listprojects']
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Creates a project.
    #
    # == Params:
    #
    # +project+::      The name of the project
    def create_project(project)
      handle_action_exceptions(__method__) do
        cmd_line = ["createproject '#{project}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Deletes a project.
    #
    # == Params:
    #
    # +project+::      The name of the project
    def delete_project(project)
      handle_action_exceptions(__method__) do
        cmd_line = ["deleteproject '#{project}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def create_project_target(target, project, machine, pool)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "createprojecttarget '#{target}' '#{project}' " \
          "'#{machine}' '#{pool}'"
        ]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def delete_project_target(target, project, machine, pool)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "deleteprojecttarget '#{target}' " \
          "'#{project}' '#{machine}' '#{pool}'"
        ]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    private

    def do_upload_playlist_file(l_playlist)
      unless File.exist?(l_playlist)
        raise RToolsHCKError.new('action/upload_playlist'),
              'Playlist file is not valid.'
      end

      r_path = "#{@winrm_fs.temp_dir}/#{SecureRandom.uuid}.xml"
      @winrm_fs.upload(l_playlist, r_path) do |cb, tb, lp, rp|
        # TODO: Check transfer
      end
      r_path
    end

    def do_list_tests(cmd_line, l_playlist)
      unless l_playlist.nil?
        r_playlist = do_upload_playlist_file(l_playlist)
        cmd_line << "-playlist #{r_playlist}"
      end

      handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
    end

    public

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
    def list_tests(target,
                   project,
                   machine,
                   pool,
                   test_type = nil,
                   test_status = nil,
                   playlist = nil)
      handle_action_exceptions(__method__) do
        cmd_line = ["listtests '#{target}' '#{project}' '#{machine}' '#{pool}'"]
        cmd_line << 'json' if @json
        cmd_line << "-#{test_type}" unless test_type.nil?
        cmd_line << "-#{test_status}" unless test_status.nil?

        do_list_tests(cmd_line, playlist)
      end
    end

    private

    def file_to_outp_dir(r_file_path)
      l_file_path = "#{@outp_dir}/#{guest_basename(r_file_path)}"
      @winrm_fs.download(r_file_path, l_file_path) do |cb, tb, lp, rp|
        # TODO: Check transfer
      end
      l_file_path
    end

    def handle_test_results_json(test_results)
      logs_zip_guest_path = test_results['content']['logszippath']
      test_results['content'].delete('logszippath')
      test_results['content']['guestlogszippath'] = logs_zip_guest_path
      unless @outp_dir.nil?
        logs_zip_host_path = file_to_outp_dir(logs_zip_guest_path)
        test_results['content']['hostlogszippath'] = logs_zip_host_path
      end
      test_results
    end

    def handle_test_results_normal(test_results, stream)
      return false unless test_results

      unless @outp_dir.nil?
        logs_zip_guest_path = stream.split("\n")
                                    .grep(/^Logs zipped to .*/)
                                    .last.split('Logs zipped to ')
                                    .last
                                    .strip
        puts "HOST: Logs zip fetched to #{file_to_outp_dir(logs_zip_guest_path)}"
      end
      test_results
    end

    def handle_test_results(test_results, stream)
      if @json
        return test_results if test_results['result'].eql?('Failure')

        handle_test_results_json(test_results)
      else
        handle_test_results_normal(test_results, stream)
      end
    end

    public

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
    def get_test_info(test, target, project, machine, pool)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "gettestinfo '#{test}' '#{target}' '#{project}' '#{machine}' " \
          "'#{pool}'"
        ]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    # == Description
    #
    # Queues a test, use get_test_results action to get the results.
    # (if the test needs two machines to run use -sup flag)
    # (if the test needs the IPv6 address of the support machine use -IPv6 flag)
    #
    # == Params:
    #
    # +test+::        The id of the test, use list_tests action to get it
    # +target+::      The key of the target, use list_machine_targets to get it
    # +project+::     The name of the project
    # +machine+::     The name of the machine as registered with the HCK\HLK
    #                 controller
    # +pool+::        The name of the pool
    # +sup+::         The name of the support machine as registered with the
    #                 HCK\HLK controller, (can be nil)
    # +parameters+::  Additional parameters in format '{ ParameterName1: Value1, ParameterName2: Value2 }', (can be nil)
    # +ipv6+::        The IPv6 address of the support machine, (can be nil)
    def queue_test(test,
                   target,
                   project,
                   machine,
                   pool,
                   sup = nil,
                   parameters = nil,
                   ipv6 = nil)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "queuetest '#{test}' '#{target}' '#{project}' '#{machine}' '#{pool}'"
        ]
        cmd_line << 'json' if @json
        cmd_line << "-sup '#{sup}'" unless sup.nil?
        cmd_line << "-parameters '#{parameters.to_json}'" unless parameters.nil?
        cmd_line << "-IPv6 '#{ipv6}'" unless ipv6.nil?

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

    private

    def do_upload_and_update_filter(l_filter)
      r_filter = run('$env:DTMBIN').strip + SecureRandom.uuid
      @winrm_fs.upload(l_filter, r_filter) do |cb, tb, lp, rp|
        # TODO: Check transfer
      end
      run('pushd $env:DTMBIN')
      run("updatefilters.exe /S #{guest_basename(r_filter)}")
      run('popd')
      @winrm_fs.delete(r_filter)
    end

    public

    # == Description
    #
    # Updates the HCK\HLK controller's filters by giving a local .sql filter file.
    #
    # == Params:
    #
    # +l_filters+::    The local filter .sql file path
    def update_filters(l_filter)
      handle_action_exceptions(__method__) do
        raise 'Filters file not valid.' unless File.exist?(l_filter)

        do_upload_and_update_filter(l_filter)
        @json ? { 'result' => 'Success' } : true
      end
    end

    # == Description
    #
    # Applies the filters on a project's test results.
    #
    # == Params:
    #
    # +project+::      The name of the project
    def apply_project_filters(project)
      handle_action_exceptions(__method__) do
        cmd_line = ["applyprojectfilters '#{project}'"]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def apply_test_result_filters(result,
                                  test,
                                  target,
                                  project,
                                  machine,
                                  pool)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "applytestresultfilters '#{result}' '#{test}' '#{target}' " \
          "'#{project}' '#{machine}' '#{pool}'"
        ]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def list_test_results(test_id, target, project, machine, pool)
      test_id = if test_id.nil?
                  '$null'
                else
                  "'#{test_id}'"
                end

      handle_action_exceptions(__method__) do
        cmd_line = [
          "listtestresults #{test_id} '#{target}' '#{project}' '#{machine}' " \
          "'#{pool}'"
        ]
        cmd_line << 'json' if @json

        handle_return(@toolshck_ether.cmd(cmd_line.join(' ')))
      end
    end

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
    def zip_test_result_logs(result_index:,
                             test:,
                             target:,
                             project:,
                             machine:,
                             pool:,
                             index_instance_id: false)
      handle_action_exceptions(__method__) do
        cmd_line = [
          "ziptestresultlogs '#{result_index}' '#{test}' '#{target}' " \
          "'#{project}' '#{machine}' '#{pool}'"
        ]
        cmd_line << 'json' if @json
        cmd_line << '-indexinstanceid' if index_instance_id

        stream = @toolshck_ether.cmd(cmd_line.join(' '))
        test_results = handle_return(stream)
        handle_test_results(test_results, stream)
      end
    end

    private

    def handle_project_package_json(project_package)
      project_package_guest_path = project_package['content']['projectpackagepath']
      project_package['content'].delete('projectpackagepath')
      project_package['content']['guestprojectpackagepath'] =
        project_package_guest_path
      unless @outp_dir.nil?
        project_package['content']['hostprojectpackagepath'] =
          file_to_outp_dir(project_package_guest_path)
      end
      project_package
    end

    def parse_project_package_guest_path(stream)
      stream.split("\n")
            .grep(/^Packaged to .*/)
            .last
            .split('Packaged to ')
            .last
            .split('...')
            .first
    end

    def handle_project_package_normal(project_package, stream)
      return false unless project_package

      unless @outp_dir.nil?
        puts 'HOST: Package fetched to ' \
             "#{file_to_outp_dir(parse_project_package_guest_path(stream))}"
      end
      project_package
    end

    def handle_project_package(ret_str)
      print 'GUEST: ' unless @json
      project_package = handle_return(ret_str)

      if @json
        return project_package if project_package['result'].eql?('Failure')

        handle_project_package_json(project_package)
      else
        handle_project_package_normal(project_package, ret_str)
      end
    end

    def package_progression_loop(current, maximum, handler)
      step = [maximum / PROGRESSION_RATE_DIVIDER, 1].max
      current = [current + step, maximum].min

      return current if current >= maximum

      steps = @toolshck_ether.cmd(current.to_s).split("\n")
      handler.call(package_progress_info_factory(steps))

      package_progression_loop(current, maximum, handler)
    end

    def package_progress_info_factory(progress_steps)
      json_progress_steps = JSON.parse("[#{progress_steps.join(',')}]")
      { 'stepscount' => progress_steps.size, 'steps' => json_progress_steps }
    end

    def dummy_package_progress_info_handler
      proc do |_progress_package|
      end
    end

    def package_progression_first_step(cmd_line, handler)
      steps = @toolshck_ether.cmd(cmd_line).split("\n")
      handler.call(package_progress_info_factory(steps))
      [JSON.parse(steps[-1])['current'], JSON.parse(steps[-1])['maximum']]
    end

    def package_progression_last_step(current, handler)
      stream = @toolshck_ether.cmd(current.to_s).split("\n")
      steps = stream[0..-2]
      handler.call(package_progress_info_factory(steps))
      stream[-1]
    end

    def handle_create_project_package(cmd_line, handler)
      current, maximum = package_progression_first_step(cmd_line, handler)
      current = package_progression_loop(current, maximum, handler)

      ret_str = package_progression_last_step(current, handler)

      handle_project_package(ret_str)
    end

    public

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
    # +driver_path+::  Provide a driver path to include, (can be nil)
    # +supplemental_path+:: Provide a supplemental path to include, (can be nil)
    # +remove_driver_signatures+:: If true, remove driver signatures before
    #                              packaging (default: false)
    def create_project_package(project, playlist = nil, handler = nil, driver_path = nil, supplemental_path = nil,
                               remove_driver_signatures: false)
      handle_action_exceptions(__method__) do
        cmd_line = ["createprojectpackage '#{project}' -rph"]
        cmd_line << 'json' if @json

        if playlist
          r_playlist = do_upload_playlist_file(playlist)
          cmd_line << "-playlist #{r_playlist}"
        end

        cmd_line << "-driver '#{driver_path}'" unless driver_path.nil?
        cmd_line << "-supplemental '#{supplemental_path}'" unless supplemental_path.nil?
        cmd_line << '-removedriversignatures' if remove_driver_signatures

        handler = dummy_package_progress_info_handler if handler.nil?
        handle_create_project_package(cmd_line.join(' '), handler)
      end
    end

    # == Description
    #
    # Gets a machine's ip address.
    #
    # == Params:
    #
    # +machine+::      The name of the machine as registered with the HCK\HLK
    #                  controller
    # +ipv6+::         Get IPv6 address, :ipv6 to enable, disabled by default
    def get_machine_ip(machine, ipv6: false)
      handle_action_exceptions(__method__) do
        cmd_line = ['ping -n 1']
        cmd_line << (ipv6 ? '-6' : '-4')
        cmd_line << machine
        ip = run(cmd_line.join(' ')).split("\r\n")[1].split[2].slice!(1..-2)
        @json ? { 'result' => 'Success', 'content' => ip } : ip
      end
    end

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
    def get_machine_system_info(machine, output_format = 'LIST')
      handle_action_exceptions(__method__) do
        info = machine_run(machine, "systeminfo /FO #{output_format.upcase}")
        @json ? { 'result' => 'Success', 'content' => info } : info
      end
    end

    # == Description
    #
    # Shuts down or restarts the studio, (you will need to reconnect after this).
    #
    # == Params:
    #
    # +restart+::      Restarts the machine, :restart to enable, disabled by
    #                  default
    def shutdown(restart: false)
      handle_action_exceptions(__method__) do
        cmd_line = ['shutdown -f -t 00']
        cmd_line << (restart ? '-r' : '-s')

        run(cmd_line.join(' '))
        @json ? { 'result' => 'Success' } : true
      end
    end

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
    def machine_shutdown(machine, restart: false)
      handle_action_exceptions(__method__) do
        cmd_line = ['shutdown -f -t 00']
        cmd_line << (restart ? '-r' : '-s')

        machine_run(machine, cmd_line.join(' '))
        @json ? { 'result' => 'Success' } : true
      end
    end

    # == Description
    #
    # Run command on a machine, (powershell).
    #
    # == Params:
    #
    # +machine+::      The name of the machine as registered with the HCK\HLK
    #                  controller
    # +cmd+::          The command to run as a string
    def run_on_machine(machine, cmd)
      handle_action_exceptions(__method__) do
        ret = machine_run(machine, cmd)
        @json ? { 'result' => 'Success', 'content' => ret } : true
      end
    end

    # == Description
    #
    # Run command on a studio, (powershell).
    #
    # == Params:
    #
    # +command+::          The command to run as a string
    def run_on_studio(command)
      handle_action_exceptions(__method__) do
        ret = run(command)
        return (@json ? { 'result' => 'Success' } : true) if ret.empty?

        @json ? { 'result' => 'Success', 'content' => ret } : true
      end
    end

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
    def upload_to_machine(machine, l_directory, r_directory = nil)
      handle_action_exceptions(__method__) do
        r_directory = do_upload_to_machine(machine, l_directory, r_directory)
        @json ? { 'result' => 'Success', 'content' => r_directory } : r_directory
      end
    end

    # == Description
    #
    # Upload file/directory to the studio machine.
    #
    # == Params:
    #
    # +l_path+::       The local file/directory path
    # +r_path+::       The remote destination path
    def upload_to_studio(l_path, r_path)
      handle_action_exceptions(__method__) do
        @winrm_fs.upload(l_path, r_path)
        @json ? { 'result' => 'Success' } : true
      end
    end

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
    def download_from_machine(machine, r_path, l_path)
      handle_action_exceptions(__method__) do
        do_download_from_machine(machine, r_path, l_path)
        @json ? { 'result' => 'Success' } : true
      end
    end

    # == Description
    #
    # Checks to see if the given path exists on the target machine.
    #
    # == Params:
    #
    # +machine+::      The name of the machine as registered with the HCK\HLK
    #                  controller
    # +r_directory+::  The remote file/directory which should be checked
    def exists_on_machine?(machine, r_path)
      handle_action_exceptions(__method__) do
        res = do_exists_on_machine?(machine, r_path)
        @json ? { 'result' => 'Success', 'content' => res } : res
      end
    end

    # == Description
    #
    # Delete the given path on the target machine.
    #
    # == Params:
    #
    # +machine+::      The name of the machine as registered with the HCK\HLK
    #                  controller
    # +r_directory+::  The remote file/directory which should be deleted
    def delete_on_machine(machine, r_path)
      handle_action_exceptions(__method__) do
        do_delete_on_machine(machine, r_path)
        @json ? { 'result' => 'Success' } : true
      end
    end

    private

    def do_upload_to_machine(machine, l_directory, r_directory = nil)
      fm = WinRM::FS::FileManager.new(machine_connection(machine))
      r_directory ||= "#{fm.temp_dir}/#{SecureRandom.uuid}"
      fm.upload(l_directory, r_directory) do |cb, tb, lp, rp|
        # TODO: Check transfer
      end
      r_directory
    rescue HTTPClient::KeepAliveDisconnected
      where = "#{machine}/winrm/run"
      raise WinrmPSRunError.new(where), "Machine #{machine} reset connection."
    end

    def do_download_from_machine(machine, r_path, l_path)
      fm = WinRM::FS::FileManager.new(machine_connection(machine))
      fm.download(r_path, l_path) do |cb, tb, lp, rp|
        # TODO: Check transfer
      end
      l_path
    rescue HTTPClient::KeepAliveDisconnected
      where = "#{machine}/winrm/run"
      raise WinrmPSRunError.new(where), "Machine #{machine} reset connection."
    end

    def do_exists_on_machine?(machine, r_path)
      fm = WinRM::FS::FileManager.new(machine_connection(machine))
      fm.exists?(r_path)
    rescue HTTPClient::KeepAliveDisconnected
      where = "#{machine}/winrm/run"
      raise WinrmPSRunError.new(where), "Machine #{machine} reset connection."
    end

    def do_delete_on_machine(machine, r_path)
      fm = WinRM::FS::FileManager.new(machine_connection(machine))
      fm.delete(r_path)
    rescue HTTPClient::KeepAliveDisconnected
      where = "#{machine}/winrm/run"
      raise WinrmPSRunError.new(where), "Machine #{machine} reset connection."
    end

    def export_certificate_script(sys_path, cer_path)
      [
        '$exportType = ' \
        '[System.Security.Cryptography.X509Certificates.X509ContentType]::Cert',
        "$cert = (Get-AuthenticodeSignature #{sys_path}).SignerCertificate",
        'if ($cert -eq $null) { exit(-1) }',
        "[System.IO.File]::WriteAllBytes('#{cer_path}', $cert" \
        '.Export($exportType))'
      ].join('; ')
    end

    def install_certificate_script(cer_path)
      [
        "certutil -enterprise -f -v -AddStore Root #{cer_path}",
        "certutil -enterprise -f -v -AddStore TrustedPublisher #{cer_path}"
      ].join('; ')
    end

    def replace_command(cmd, replacement_list)
      result = cmd
      replacement_list.each do |k, v|
        # If replacement is a String it will be substituted for the matched text.
        # It may contain back-references to the pattern's capture groups of the form \d,
        # where d is a group number, or \k<n>, where n is a group name.
        # In the block form, the current match string is passed in as a parameter,
        # and variables such as $1, $2, $`, $&, and $' will be set appropriately.
        # The value returned by the block will be substituted for the match on each call.
        result = result.gsub(k) { v }
      end
      result
    end

    def install_driver_list(r_directory, windows_path)
      {
        '@driver_dir@' => r_directory,
        '@inf_path@' => windows_path
      }
    end

    def get_custom_command(r_directory, windows_path, custom_cmd)
      replace_command(custom_cmd, install_driver_list(r_directory, windows_path))
    end

    def install_driver_command(r_directory, windows_path, install_method, custom_cmd = nil)
      case install_method
      when 'PNP'
        "pnputil -i -a #{windows_path}"
      when 'NON-PNP'
        'RUNDLL32.EXE SETUPAPI.DLL,InstallHinfSection ' \
        "DefaultInstall 128 #{windows_path}"
      when 'custom'
        get_custom_command(r_directory, windows_path, custom_cmd)
      end
    end

    def install_certificate(machine, windows_path, sys_file = nil)
      sys_path = if sys_file.nil?
                   windows_path.sub('.inf', '.sys')
                 else
                   "#{guest_dirname(windows_path)}\\#{sys_file}"
                 end
      cer_path = guest_dirname(windows_path) + "\\#{SecureRandom.uuid}.cer"
      logger('debug', "Export and install certificate from #{sys_path}")

      machine_run(machine, export_certificate_script(sys_path, cer_path))
      machine_run(machine, install_certificate_script(cer_path))
    rescue WinrmPSRunError => e
      raise RToolsHCKActionError.new("action/install_machine_driver_package/#{e.where}"),
            'Installing certificate failed, maybe digital signature is missing. ' \
            "Previous exception #{e.message}"
    end

    def do_install_machine_driver_package(machine,
                                          install_method,
                                          l_directory,
                                          inf_file,
                                          options)
      custom_cmd = options[:custom_cmd]
      force_install_cert = options[:force_install_cert]
      sys_file = options[:sys_file]

      r_directory = do_upload_to_machine(machine, l_directory).tr('/', '\\')
      windows_path = "#{r_directory}\\#{inf_file}"
      install_certificate(machine, windows_path, sys_file) if install_method.eql?('PNP') || force_install_cert
      machine_run(machine, install_driver_command(r_directory, windows_path, install_method, custom_cmd))

      install_driver_list(r_directory, windows_path)
    end

    public

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
    def install_machine_driver_package(machine,
                                       install_method,
                                       l_directory,
                                       inf_file,
                                       options = {})
      handle_action_exceptions(__method__) do
        file = File.join(l_directory, inf_file)
        raise 'Inf file not valid.' unless File.exist?(file)

        driver_info = do_install_machine_driver_package(machine,
                                                        install_method,
                                                        l_directory,
                                                        inf_file,
                                                        options)
        @json ? { 'result' => 'Success', 'content' => driver_info } : driver_info
      end
    end

    # == Description
    #
    # Tries to regain the connection to the guest machine using the given
    # credentials and addresses on initialization.
    #
    def reconnect
      handle_action_exceptions(__method__) do
        priv_close
        load_winrm_ps
        load_toolshck
        @json ? { 'result' => 'Success' } : true
      end
    end

    private

    def priv_close
      return if @no_studio

      unload_toolshck
      unload_winrm_ps
    end

    def unload_winrm_ps
      logger('debug', 'close/unload_winrm_ps') { 'unloading winrm shell...' }
      @winrm_ps&.close
      logger('debug', 'close/unload_winrm_ps') { 'winrm shell unloaded!' }
    rescue StandardError => e
      log_exception(e, 'warn')
    end

    def unload_ether
      @toolshck_ether&.close
      logger('debug', 'close/unload_ether') { 'ether unloaded!' }
    rescue StandardError => e
      log_exception(e, 'warn')
    end

    def unload_toolshck
      unload_ether
    end

    def check_connection
      cmd_line = ['ping']

      if @toolshck_ether.cmd(cmd_line.join(' ')).include?('pong')
        @json ? { 'result' => 'Success' } : true
      else
        raise RToolsHCKActionError.new('action/connection_check'),
              "something went wrong, 'pong' was not received."
      end
    end

    public

    # == Description
    #
    # Checks if connection is still alive.
    #
    def connection_check
      handle_action_exceptions(__method__) do
        check_connection
      end
    rescue RToolsHCKConnectionError => e
      if @json
        { 'result' => 'Failure', 'message' => e.message }
      else
        puts "WARNING: #{e.message}"
        false
      end
    end

    # == Description
    #
    # Closes the instance and shuts down the studio.
    #
    def close_and_shutdown
      handle_action_exceptions(__method__) do
        unload_toolshck
        shutdown
        unload_winrm_ps
        logger('info', 'close_and_shutdown') { 'done!' }
        @closed = true
        @json ? { 'result' => 'Success' } : true
      end
    end

    # == Description
    #
    # Closes the instance.
    #
    def close
      handle_action_exceptions(__method__) do
        priv_close
        logger('info', 'close') { 'done!' }
        @closed = true
        @json ? { 'result' => 'Success' } : true
      end
    end

    # == Description
    #
    # Boolean method to the instance being closed.
    #
    def closed?
      @closed
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/ParameterLists
