# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # HCKClient class
  class HCKClient
    # Client cooldown timeout in seconds, to prevent hangs (30 minutes)
    CLIENT_COOLDOWN_TIMEOUT = 1800

    # Client cooldown sleep after thread is joined in seconds
    CLIENT_COOLDOWN_SLEEP = 60

    HLK_COMMUNICATION_SERVICE = 'HLKsvc'

    # Deadline for a client to join a pool, in seconds
    CLIENT_POOL_WAIT_TIMEOUT = 900

    # Grace period before service checks begin, to let boot-time auto-start complete
    SERVICE_CHECK_GRACE = 120

    SERVICE_CHECK_INTERVAL = 30

    attr_reader :name, :kit, :target, :replacement_map

    def initialize(setup_manager, scope, studio, name, run_opts)
      @project = setup_manager.project
      @logger = @project.logger
      @studio = studio
      @name = name
      @kit = setup_manager.kit
      @logger.info("Starting client #{name}")
      @runner = setup_manager.run_client(scope, @name, run_opts)
      scope << self
      @setup_manager = setup_manager
      @replacement_map = @project.project_replacement_map.merge(setup_manager.client_replacement_map(name))
    end

    def pool
      @studio.list_pools.each do |pool|
        return pool['name'] if pool['machines'].any? { |machine| machine['name']&.casecmp?(@name) }
      end
    end

    def keep_snapshot
      @runner.keep_snapshot
    end

    def search_target
      @target = Targets.new(self, @project, @tools, pool).search_target
    end

    def add_target_to_project
      @target = Targets.new(self, @project, @tools, pool).add_target_to_project
    end

    def configure_machine
      @logger.info("Configuring client #{@name}...")
      reset_to_ready_state
      sleep CLIENT_COOLDOWN_SLEEP
    end

    def reconfigure_machine
      delete_machine
      restart_machine
      return_when_client_up
      move_machine_to_pool
      configure_machine
    end

    def delete_machine
      @tools.delete_machine(@name, pool)
    end

    def restart_machine
      @logger.info("Restarting #{@name}")
      @tools.restart_machine(@name)
    end

    def move_machine_to_pool
      @logger.info("Moving #{@name} to pool")
      @tools.move_machine(@name, pool, @project.engine_tag)
    end

    def set_machine_ready
      @logger.info("Setting #{@name} state to Ready")
      return if @tools.set_machine_ready(@name, pool)

      raise ClientRunError, "Couldn't set #{@name} state to Ready"
    end

    def pool_only_client?
      @project.engine.platform_clients.pool_only?(@name)
    end

    def post_start_commands
      return [] if pool_only_client?

      (@project.engine.drivers.flat_map(&:post_start_commands) +
       @project.engine.extensions.flat_map(&:post_start_commands) +
        @setup_manager.client_post_start_commands).select(&:guest_run)
    end

    def run_post_start_commands
      post_start_commands&.each do |command|
        command_execution_manager.execute(command)
      end
    end

    def command_execution_manager
      @command_execution_manager ||= CommandExecutionManager.new(
        project: @project,
        tools: @tools,
        machines: [@name],
        init_opts: {
          reboot_callback: ->(_name) { reconfigure_machine }
        }
      )
    end

    def install_driver(driver)
      path = @project.options.test.driver_path
      method = driver.install_method.to_s
      inf = driver.inf

      @logger.info("Installing #{method} driver #{inf} in #{@name}")
      @tools.install_machine_driver_package(@name, method, path, inf,
                                            custom_cmd: driver.install_command,
                                            sys_file: driver.sys,
                                            force_install_cert: driver.install_cert)
    end

    def insert_driver_replacement(driver, one_driver, replacement)
      client_replacement = replacement.transform_keys { |k| k.dup.insert(1, "#{driver.short}.") }
      @replacement_map.merge!(client_replacement)

      # If there is only one driver, we can use generic keys without driver short name.
      return unless one_driver

      @replacement_map.merge!({ '@driver_short_name@' => driver.short })
      @replacement_map.merge!(replacement)
    end

    def install_drivers
      one_driver = @project.engine.drivers.one?

      @project.engine.drivers&.each do |driver|
        if driver.install_method == AutoHCK::Models::DriverInstallMethods::NoDrviver
          @project.logger.info("Driver installation skipped for #{driver.name} in #{@name}")
          next
        end

        driver_replacement = install_driver(driver)
        insert_driver_replacement(driver, one_driver, driver_replacement)
      end

      @logger.debug("Driver replacement list: #{@replacement_map.dump_string}")
    end

    def copy_dvl
      path = @project.options.test.driver_path

      @logger.info('Looking for DVL logs')
      Dir.glob("#{path}/*.DVL.XML", File::FNM_CASEFOLD).each do |dvl_file|
        dvl_file_name = File.basename(dvl_file)
        @logger.info("Uploading #{dvl_file_name} log to #{@name}")
        @tools.upload_to_machine(@name, dvl_file, "C:/DVL/#{dvl_file_name}")
      end
    end

    def machine_info
      machines = @studio.list_pools.flat_map { |pool| pool['machines'] }
      machines.detect { |machine| machine['name']&.casecmp?(@name) }
    end

    def recognize_client_wait
      @logger.info("Waiting for client #{@name} to be recognized in Default Pool")
      wait_for_pool_membership('Default Pool')
      @logger.info("Client #{@name} recognized")
    end

    def initialize_client_wait
      @logger.info("Waiting for client #{@name} initialization")
      sleep 5 while machine_info['state'].eql?('Initializing')
      @logger.info("Client #{@name} initialized")
    end

    def return_when_client_up
      recognize_client_wait
      initialize_client_wait
    end

    def return_when_client_restored
      @logger.info("Waiting for client #{@name} to rejoin pool #{@project.engine_tag}")
      wait_for_pool_membership(@project.engine_tag)
      @logger.info("Client #{@name} rejoined pool #{@project.engine_tag}")
    end

    # Waits for the client to join the given pool, bounded by
    # CLIENT_POOL_WAIT_TIMEOUT. Monitors the HLK communication service while
    # waiting; the raised ClientRunError lets the setup retry re-boot the client.
    def wait_for_pool_membership(pool_name)
      started = monotonic_time
      deadline = started + CLIENT_POOL_WAIT_TIMEOUT
      next_service_check = started + SERVICE_CHECK_GRACE
      last_service_status = nil
      loop do
        return if pool == pool_name

        now = monotonic_time
        raise pool_wait_timeout_error(pool_name, now - started, last_service_status) if now >= deadline

        if now >= next_service_check
          status = ensure_hlk_communication_service
          last_service_status = status unless status.nil?
          next_service_check = now + SERVICE_CHECK_INTERVAL
        end

        sleep 5
      end
    end

    def pool_wait_timeout_error(pool_name, elapsed, last_service_status)
      ClientRunError.new("Client #{@name} did not join pool '#{pool_name}' after waiting " \
                         "#{elapsed.to_i} seconds (HLK communication service " \
                         "'#{HLK_COMMUNICATION_SERVICE}' status: #{last_service_status || 'unknown'})")
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Starts the HLK communication service when stopped. Returns the status,
    # or nil when the client can not be reached.
    def ensure_hlk_communication_service
      status = hlk_communication_service_status
      if status == 'Missing'
        raise ClientRunError, "HLK communication service '#{HLK_COMMUNICATION_SERVICE}' " \
                              "is missing on client #{@name}"
      end
      return status unless status == 'Stopped'

      @logger.warn("HLK communication service '#{HLK_COMMUNICATION_SERVICE}' is stopped " \
                   "on #{@name}, trying to start it")
      begin
        @tools.run_on_machine(@name, 'HLK communication service start',
                              "Start-Service #{HLK_COMMUNICATION_SERVICE} -ErrorAction Stop",
                              max_attempts: 1)
      rescue *service_check_transient_errors => e
        @logger.warn("Starting HLK communication service on #{@name} failed: #{e.message}")
      end
      status
    end

    def hlk_communication_service_status
      cmd = "$service = Get-Service #{HLK_COMMUNICATION_SERVICE} -ErrorAction SilentlyContinue; " \
            "if ($null -eq $service) { 'Missing' } else { $service.Status.ToString() }"
      @tools.run_on_machine(@name, 'HLK communication service status check', cmd, max_attempts: 1).strip
    rescue *service_check_transient_errors => e
      @logger.debug("HLK communication service status check failed on #{@name}: #{e.message}")
      nil
    end

    # Errors treated as transient by the service checks (client unreachable
    # or booting); anything else is a real error and propagates. Listed
    # explicitly because some escape RToolsHCK's SSH_ACTION_ERRORS wrapping.
    def service_check_transient_errors
      [
        Tools::ToolsHCKError,
        HTTPClient::TimeoutError,
        HTTPClient::BadResponseError,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT,
        Errno::ECONNRESET,
        Errno::ENETUNREACH,
        SocketError,
        Timeout::Error
      ]
    end

    def prepare_machine
      @logger.info("Preparing client #{@name}...")
      @project.extra_sw_manager.install_software_before_driver(@tools, @name)
      install_drivers
      copy_dvl
      @project.extra_sw_manager.install_software_after_driver(@tools, @name)
    end

    def configure_restored
      return_when_client_restored
      initialize_client_wait
      configure_machine
      search_target unless pool_only_client?
    end

    def configure_fresh(run_only:)
      unless pool == @project.engine_tag
        return_when_client_up
        if run_only
          @logger.info("Preparing client skipped #{@name}...")

          Thread.exit
        end
        if pool_only_client?
          @logger.info("Skipping driver preparation for #{@name} " \
                       "(role: #{@project.engine.platform_clients.role_for(@name)})")
        else
          prepare_machine
        end
        move_machine_to_pool
      end

      configure_machine
      run_post_start_commands
      add_target_to_project unless pool_only_client?
    end

    def configure(run_only: false)
      @tools = @studio.tools
      @cooldown_thread = Thread.new do
        @project.restored? ? configure_restored : configure_fresh(run_only:)
      end
    end

    def synchronize
      return unless @cooldown_thread&.join(CLIENT_COOLDOWN_TIMEOUT).nil?

      e_message = "Timeout expired for the cooldown thread of client #{@name}"
      raise ClientRunError, e_message
    end

    def not_ready?
      machine_info['state'].eql?('NotReady')
    end

    def reset_to_ready_state
      return unless not_ready?

      @logger.info("Setting client #{@name} state to Ready")
      set_machine_ready
    end

    def close
      @logger.info("Exiting HLKClient #{@name}")
      @cooldown_thread&.exit
    end
  end
end
