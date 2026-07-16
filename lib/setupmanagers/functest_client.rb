# frozen_string_literal: true

module AutoHCK
  # Setup manager for the functest engine.
  #
  # Boots the client VM and prepares it for functest runs (no HLK Studio).
  class FunctestClient
    TEST_BINARIES_REMOTE_PATH = 'C:\\AutoHCK\\test_binaries'

    attr_reader :name, :tools, :replacement_map

    def initialize(setup_manager, scope, name, run_opts = nil)
      @project = setup_manager.project
      @logger = @project.logger
      @setup_manager = setup_manager
      @name = name
      @logger.info("Starting functest client #{name}")
      @runner = setup_manager.run_client(scope, name, run_opts)
      scope << self
      @replacement_map = @project.project_replacement_map.merge(setup_manager.client_replacement_map(name))
    end

    def prepare_machine
      @logger.info("Preparing client #{@name}...")
      @tools = FunctestTools.new(@project, @name, client_winrm_addr)
      @project.extra_sw_manager.install_software_before_driver(@tools, @name)
      install_drivers
      copy_test_binaries
      @project.extra_sw_manager.install_software_after_driver(@tools, @name)
    end

    def command_execution_manager
      raise AutoHCKError, 'Tools not initialized; call prepare_machine first' unless @tools

      @command_execution_manager ||= CommandExecutionManager.new(
        project: @project,
        tools: @tools,
        machines: [@name],
        init_opts: {
          reboot_strategy: CommandExecutionManager::RebootStrategy[:WinrmPoll]
        }
      )
    end

    def close
      @logger.info("Exiting FunctestClient #{@name}")
    end

    private

    def client_winrm_addr
      client = @project.engine_platform.clients.values.find { |c| c.name == @name }
      raise AutoHCKError, "No platform client entry found for #{@name}" unless client
      raise AutoHCKError, "winrm_addr missing for client #{@name} in platform config" unless client.winrm_addr

      { addr: client.winrm_addr }
    end

    def insert_driver_replacement(driver, replacement)
      client_replacement = replacement.transform_keys { |k| k.dup.insert(1, "#{driver.short}.") }
      @replacement_map.merge!(client_replacement)

      # If there is only one driver, we can use generic keys without driver short name.
      return unless @project.engine.drivers.one?

      @replacement_map.merge!({ '@driver_short_name@' => driver.short })
      @replacement_map.merge!(replacement)
    end

    def copy_test_binaries
      test_binaries_path = @project.options.test.test_binaries_path
      return unless test_binaries_path

      @logger.info("Copying test binaries to client #{@name}...")
      remote_path = @tools.upload_to_machine(@name, test_binaries_path, TEST_BINARIES_REMOTE_PATH)
      @replacement_map.merge!({ '@test_binaries_dir@' => remote_path })
    end

    def install_drivers
      driver_path = @project.options.test.driver_path
      drivers = @project.engine.drivers

      return if drivers.empty?
      return if skip_drivers_installation?(driver_path)

      raise AutoHCKError, '--driver-path is required when drivers are configured' if driver_path.nil?

      @logger.info('Installing drivers on client VM...')
      drivers.each do |driver|
        driver_replacement = install_driver(driver, driver_path)
        insert_driver_replacement(driver, driver_replacement) unless driver_replacement.nil?
      end
    end

    def skip_drivers_installation?(driver_path)
      return false unless driver_path.nil? && @project.options.test.test_binaries_path

      @logger.info('--test-binaries-path provided without --driver-path: ' \
                   'skipping driver installation, device(s) attached only')
      true
    end

    def install_driver(driver, driver_path)
      if driver.install_method == Models::DriverInstallMethods::NoDrviver
        @logger.info("Driver installation skipped for #{driver.name}")
        return
      end

      @logger.info("Installing #{driver.name} (#{driver.inf}) via #{driver.install_method}")
      @tools.install_machine_driver_package(
        @name,
        driver.install_method.to_s,
        driver_path,
        driver.inf,
        custom_cmd: driver.install_command,
        sys_file: driver.sys,
        force_install_cert: driver.install_cert
      )
    end
  end
end
