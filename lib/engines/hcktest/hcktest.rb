# frozen_string_literal: true

require './lib/setupmanagers/hckstudio'
require './lib/setupmanagers/hckclient'
require './lib/auxiliary/diff_checker'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/resource_scope'
require './lib/auxiliary/zip_helper'

# AutoHCK module
module AutoHCK
  # HCKTest class
  class HCKTest
    include Helper
    attr_reader :config, :drivers, :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    CONFIG_JSON = 'lib/engines/hcktest/hcktest.json'
    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'
    SVVP_JSON = 'svvp.json'
    ENGINE_MODE = 'test'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{tag}.log")
      @config = Json.read_json(CONFIG_JSON, @logger)
      @platform = read_platform
      @driver_path = @project.options.test.driver_path
      @drivers = find_drivers
      prepare_extra_sw
      validate_paths unless @driver_path.nil?
      init_workspace
    end

    def prepare_extra_sw
      @drivers.each do |driver|
        next if driver['extra_software'].nil?

        @project.extra_sw_manager.prepare_software_packages(
          driver['extra_software'], @platform['kit'], ENGINE_MODE
        )
      end

      return if @platform['extra_software'].nil?

      @project.extra_sw_manager.prepare_software_packages(
        @platform['extra_software'], @platform['kit'], ENGINE_MODE
      )
    end

    def init_workspace
      @workspace_path = [@project.workspace_path,
                         tag, @project.timestamp].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @project.logger.warn('Workspace path already exists')
      end
      @project.move_workspace_to(@workspace_path.to_s)
    end

    def validate_paths
      normalize_paths
      @drivers.each do |driver|
        method = driver['install_method']
        if method == 'no-drv'
          @project.logger.info("Driver paths validation skipped for #{driver['name']}")
          next
        end

        paths = [
          "#{@driver_path}/#{driver['inf']}",
          "#{@driver_path}/#{driver['short']}/#{driver['inf']}"
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
        @svvp_info = Json.read_json(SVVP_JSON, @project.logger)
        driver_names = @svvp_info['drivers']
      else
        driver_names = @project.options.test.drivers
        raise(AutoHCKError, 'Unsupported configuration. Drivers count is not equals 1') if driver_names.count != 1
      end

      driver_names
    end

    def read_driver(driver)
      driver_json = "#{DRIVERS_JSON_DIR}/#{driver}.json"

      @logger.info("Loading driver: #{driver}")
      Json.read_json(driver_json, @logger)
    rescue Errno::ENOENT
      @logger.fatal("#{driver} does not exist")
      raise(InvalidConfigFile, "#{driver} does not exist")
    end

    def find_drivers
      driver_names.map do |short_name|
        driver = read_driver(short_name)

        driver['short'] = short_name

        driver
      end
    end

    def target
      if @project.options.test.svvp
        {
          'name' => @clients.values[0].name,
          'type' => @svvp_info['type'],
          'select_test_names' => @svvp_info['select_test_names'],
          'reject_test_names' => @svvp_info['reject_test_names']
        }
      else
        driver = drivers.first
        {
          'name' => driver['name'],
          'type' => driver['type'],
          'select_test_names' => driver['select_test_names'],
          'reject_test_names' => driver['reject_test_names']
        }
      end
    end

    def read_platform
      platform_name = @project.options.test.platform
      platform_json = "#{PLATFORMS_JSON_DIR}/#{platform_name}.json"

      @logger.info("Loading platform: #{platform_name}")
      unless File.exist?(platform_json)
        @logger.fatal("#{platform_name} does not exist")
        raise(InvalidConfigFile, "#{platform_name} does not exist")
      end

      Json.read_json(platform_json, @logger)
    end

    def run_studio(scope, run_opts = {})
      @studio = @project.setup_manager.run_hck_studio(scope, run_opts)
    end

    def run_clients(scope, run_opts = {})
      @clients = {}
      @platform['clients'].each_value do |client|
        @clients[client['name']] = @project.setup_manager.run_hck_client(scope, @studio, client['name'], run_opts)

        break if @project.options.test.svvp
        break unless @drivers.any? { |d| d['support'] }
      end
      return unless @clients.empty?

      raise InvalidConfigFile, 'Clients configuration for \
                                this platform is incorrect'
    end

    def configure_clients
      run_only = @project.options.test.manual && @project.options.test.driver_path.nil?

      @clients.each_value do |client|
        client.configure(run_only:)
      end
    end

    def configure_setup_and_synchronize
      @studio.configure(@platform['clients'])
      configure_clients
      @clients.each_value(&:synchronize)
      @client1 = @clients.values[0]
      @client2 = @clients.values[1]
      @client1.support = @client2
      @studio.keep_snapshot
      @clients.each_value(&:keep_snapshot)
    end

    def run_and_configure_setup(scope)
      retries ||= 0

      scope.transaction do |tmp_scope|
        run_studio tmp_scope
        sleep 5 until @studio.up?
        run_clients tmp_scope, keep_alive: true

        configure_setup_and_synchronize
      end
    rescue AutoHCKError => e
      @project.logger.warn("Running and configuring setup failed: (#{e.class}) #{e.message}")
      raise e unless (retries += 1) < AUTOHCK_RETRIES

      @project.logger.info('Trying again to run and configure setup')
      retry
    end

    def upload_driver_package
      @project.logger.info('Uploading driver package')

      r_name = "#{tag}.zip"
      zip_path = "#{@workspace_path}/#{r_name}"
      create_zip_from_directory(zip_path, @driver_path)
      @project.result_uploader.upload_file(zip_path, r_name)
    end

    def tag
      if @project.options.test.svvp
        "svvp-#{@project.options.test.platform}"
      else
        "#{@project.options.test.drivers.sort.join('-')}-#{@project.options.test.platform}"
      end
    end

    def manual_run
      ResourceScope.open do |scope|
        run_studio(scope, { dump_only: true })
        run_clients(scope, { dump_only: true })
      end
    end

    def auto_run
      ResourceScope.open do |scope|
        run_and_configure_setup scope
        client = @client1
        client.run_tests
        client.create_package
      end
    end

    def run
      upload_driver_package unless @driver_path.nil?

      if @project.options.test.manual
        @project.logger.info('AutoHCK started in manual mode')

        manual_run

        @project.logger.info("Find all scripts in folder: #{@project.workspace_path}")
      else
        auto_run
      end
    end

    def result_uploader_needed?
      true
    end
  end
end
