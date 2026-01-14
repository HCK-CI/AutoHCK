# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # HCKTest class
  class HCKTest
    extend T::Sig
    include Helper

    attr_reader :config, :drivers, :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    CONFIG_JSON = 'lib/engines/hcktest/hcktest.json'
    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'
    SVVP_JSON = 'svvp.json'
    ENGINE_MODE = 'test'
    AUTOHCK_RETRIES = 5

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.engine_tag}.log")
      @config = Models::HCKTestConfig.from_json_file(CONFIG_JSON, @logger)
      @driver_path = @project.options.test.driver_path
      @drivers = find_drivers
      prepare_extra_sw
      validate_paths unless @driver_path.nil?
    end

    def test_steps
      (@tests&.tests || []) + (@tests&.rejected_tests || [])
    end

    def prepare_extra_sw
      extra_softwares = []
      extra_softwares += @drivers.flat_map(&:extra_software)
      extra_softwares += @project.engine_platform['extra_software'] || []

      @project.extra_sw_manager.prepare_software_packages(
        extra_softwares, @project.engine_platform['kit'], ENGINE_MODE
      )
    end

    def validate_paths
      normalize_paths
      @drivers.each do |driver|
        if driver.install_method == Models::DriverInstallMethods::NoDrviver
          @project.logger.info("Driver paths validation skipped for #{driver.name}")
          next
        end

        paths = [
          "#{@driver_path}/#{driver.inf}",
          "#{@driver_path}/#{driver.short}/#{driver.inf}"
        ]
        next if paths.any? { |p| File.exist?(p) }

        @project.logger.fatal('Driver paths are not valid')
        raise(InvalidPathError, "Driver paths #{paths.join(', ')} are not valid")
      end
    end

    def normalize_paths
      @driver_path.chomp!('/')
    end

    def driver_names
      if @project.options.test.svvp
        @svvp_info = Models::SVVPConfig.from_json_file(SVVP_JSON, @project.logger)
        driver_names = @svvp_info.drivers
      else
        driver_names = @project.options.test.drivers
        raise(AutoHCKError, 'Unsupported configuration. Drivers count is not equals 1') if driver_names.count != 1
      end

      driver_names
    end

    sig { params(driver: String).returns(Models::Driver) }
    def read_driver(driver)
      driver_json = "#{DRIVERS_JSON_DIR}/#{driver}.json"

      @logger.info("Loading driver: #{driver}")
      Models::Driver.from_json_file(driver_json, @logger)
    end

    sig { returns(T::Array[Models::Driver]) }
    def find_drivers
      driver_names.filter_map do |short_name|
        driver = read_driver(short_name)
        next if driver.device == @project.options.test.boot_device
        next if driver.device == @project.options.common.client_ctrl_net_dev
        next if driver.device == @project.engine_platform.dig('clients_options', 'ctrl_net_device')

        driver.short = short_name

        driver
      end
    end

    def target
      if @project.options.test.svvp
        {
          'name' => @clients.values[0].name,
          'type' => @svvp_info.type,
          'select_test_names' => @svvp_info.select_test_names,
          'reject_test_names' => @svvp_info.reject_test_names
        }
      else
        driver = drivers.first
        {
          'name' => driver.name,
          'type' => driver.type,
          'select_test_names' => driver.select_test_names,
          'reject_test_names' => driver.reject_test_names
        }
      end
    end

    def self.platform(logger, options)
      platform_name = options.test.platform
      platform = Json.read_json("#{PLATFORMS_JSON_DIR}/#{platform_name}.json", logger)

      platform['clients_options'] ||= {}
      platform['clients_options']['vbs_state'] ||= options.test.enable_vbs

      if options.test.svvp
        svvp_info = Models::SVVPConfig.from_json_file(SVVP_JSON, logger)
        platform['clients_options'].merge!(svvp_info.clients_options.serialize)
      end

      platform
    end

    def run_studio(scope, run_opts = {})
      @studio = @project.setup_manager.run_hck_studio(scope, run_opts)
    end

    def run_clients(scope, run_opts = {})
      @clients = {}
      @project.engine_platform['clients'].each_value do |client|
        @clients[client['name']] = @project.setup_manager.run_hck_client(scope, @studio, client['name'], run_opts)

        break if @project.options.test.svvp
        break unless @drivers.any?(&:support)
      end
      return unless @clients.empty?

      raise InvalidConfigFile, 'Clients configuration for \
                                this platform is incorrect'
    end

    def post_start_commands
      (@drivers.flat_map(&:post_start_commands) +
        @project.setup_manager.client_post_start_commands).select(&:host_run)
    end

    def run_clients_post_start_host_commands
      post_start_commands.each do |command|
        @logger.info("Running command (#{command.desc}) on host")
        run_cmd(command.host_run)
      end
    end

    def configure_and_synchronize_clients
      run_only = @project.options.test.manual && @project.options.test.driver_path.nil?

      @clients.each_value do |client|
        client.configure(run_only:)
      end

      run_clients_post_start_host_commands
      @clients.each_value(&:synchronize)
    end

    def configure_setup_and_synchronize
      return configure_and_synchronize_clients unless @studio.tools.nil?

      @studio.configure(@project.engine_platform['clients'])
      configure_and_synchronize_clients
      @studio.keep_snapshot
      @clients.each_value(&:keep_snapshot)
    end

    def run_clients_and_configure_setup(scope, **opts)
      retries = 0
      begin
        scope.transaction do |tmp_scope|
          run_clients tmp_scope, keep_alive: true, **opts

          configure_setup_and_synchronize
        end
      rescue AutoHCKError => e
        @project.logger.warn("Running and configuring setup failed: (#{e.class}) #{e.message}")
        raise e unless (retries += 1) < AUTOHCK_RETRIES

        @project.logger.info('Trying again to run and configure setup')
        retry
      end
    end

    def upload_driver_package
      @project.logger.info('Uploading driver package')

      r_name = "#{@project.engine_tag}.zip"
      zip_path = "#{@project.workspace_path}/#{r_name}"
      create_zip_from_directory(zip_path, @driver_path)
      @project.result_uploader.upload_file(zip_path, r_name)
    end

    def self.tag(options)
      base_tag = if options.test.svvp
                   "svvp-#{options.test.platform}"
                 else
                   "#{options.test.drivers.sort.join('-')}-#{options.test.platform}"
                 end

      # Append tag_suffix if provided to prevent name conflicts when using shared controller
      suffix = options.test.tag_suffix&.strip
      if suffix && !suffix.empty?
        "#{base_tag}-#{suffix}"
      else
        base_tag
      end
    end

    def dump_run
      ResourceScope.open do |scope|
        run_studio(scope, { dump_only: true })
        run_clients(scope, { dump_only: true })
      end
    end

    def pause_run
      @project.logger.info('AutoHCK switched in manual mode. Waiting for manual exit.')
      @project.logger.info("Type 'exit' and press ENTER to exit manul mode")

      # rubocop:disable Lint/Debugger
      binding.irb
      # rubocop:enable Lint/Debugger

      @project.logger.info('Manual exit. AutoHCK will continue.')
    end

    def prepare_tests
      client, support = @clients.values

      @tests = Tests.new(client, support, @project, client.target, @studio.tools)

      if client.target.nil?
        raise EngineError, 'HLK test target is not defined' unless @project.options.test.manual

        @project.logger.info('HLK test target is not defined, allow in manual mode')
      end

      @test_list = @tests.update_tests(log: true)
    end

    def auto_run
      ResourceScope.open do |scope|
        run_studio scope
        sleep 5 until @studio.up?

        run_tests_without_config
        run_tests_with_config

        @tests.create_project_package
      end
    end

    def run_tests_without_config
      ResourceScope.open do |scope|
        run_clients_and_configure_setup scope
        prepare_tests

        @logger.info('Client ready, running basic tests')
        @tests.run(@test_list - group_tests_by_config.values.flatten)

        pause_run if @project.options.test.manual
      end
    end

    def run_tests_with_config
      group_tests_by_config.each do |group, tests|
        next if tests.empty?

        ResourceScope.open do |scope|
          run_clients_and_configure_setup(scope, group => true, create_snapshot: false, boot_from_snapshot: true)

          @logger.info("Clients ready, running #{group} tests")
          @tests.run(tests)

          pause_run if @project.options.test.manual
        end
      end
    end

    def group_tests_by_config
      grouped_tests = { secure: [] }

      tests_config = @config.tests_config + @drivers.flat_map(&:tests_config)

      tests_config.each do |test_group|
        selected_tests = @test_list.select { |test| test_group.tests.include?(test.name) }
        grouped_tests[:secure] += selected_tests if test_group.secure
      end

      grouped_tests
    end

    def run
      upload_driver_package unless @driver_path.nil?

      if @project.options.test.dump
        @project.logger.info('AutoHCK started in dump only mode')

        dump_run

        @project.logger.info("Find all scripts in folder: #{@project.workspace_path}")
        @project.logger.warn('Dump mode is only for basic tests.')
        @project.logger.warn('For specific configurations (e.g., Secure Boot tests), update scripts manually.')
      else
        auto_run
      end
    end

    def result_uploader_needed?
      true
    end
  end
end
