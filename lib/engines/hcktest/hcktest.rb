# frozen_string_literal: true

require './lib/setupmanagers/hckstudio'
require './lib/setupmanagers/hckclient'
require './lib/auxiliary/diff_checker'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/zip_helper'

# AutoHCK module
module AutoHCK
  # HCKTest class
  class HCKTest
    include Helper
    attr_reader :drivers, :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    DRIVERS_JSON = 'drivers.json'
    SVVP_JSON = 'svvp.json'
    ENGINE_MODE = 'test'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{tag}.log")
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
        @svvp_info = read_json(SVVP_JSON, @project.logger)
        driver_names = @svvp_info['drivers']
      else
        driver_names = @project.options.test.drivers
        raise(AutoHCKError, 'Unsupported configuration. Drivers count is not equals 1') if driver_names.count != 1
      end

      driver_names
    end

    def find_drivers
      drivers_info = read_json(DRIVERS_JSON, @project.logger)

      driver_names.map do |short_name|
        @project.logger.info("Loading driver: #{short_name}")
        res = drivers_info.find { |driver| driver['short'] == short_name }
        @project.logger.fatal("#{short_name} does not exist") unless res
        res || raise(InvalidConfigFile, "#{short_name} does not exist")
      end
    end

    def target
      if @project.options.test.svvp
        {
          'name' => @clients.values[0].name,
          'type' => @svvp_info['type'],
          'playlist' => @svvp_info['playlist'],
          'blacklist' => @svvp_info['blacklist']
        }
      else
        driver = drivers.first
        {
          'name' => driver['name'],
          'type' => driver['type'],
          'playlist' => driver['playlist'],
          'blacklist' => driver['blacklist']
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

      read_json(platform_json, @logger)
    end

    def initialize_clients
      @clients = {}
      @platform['clients'].each do |_name, client|
        @clients[client['name']] = @project.setup_manager.create_client(client['name'])

        break if @project.options.test.svvp
        break unless @drivers.any? { |d| d['support'] }
      end
      return unless @clients.empty?

      raise InvalidConfigFile, 'Clients configuration for \
                                this platform is incorrect'
    end

    def synchronize_clients(exit: false)
      @clients.each_value do |client|
        client.synchronize(exit: exit)
      end
    end

    def configure_clients
      run_only = @project.options.test.manual && @project.options.test.driver_path.nil?

      @clients.each_value do |client|
        client.configure(run_only: run_only)
      end
    end

    def configure_setup_and_synchronize
      @studio.configure(@platform['clients'])
      configure_clients
      synchronize_clients
      @client1 = @clients.values[0]
      @client2 = @clients.values[1]
      @client1.support = @client2
    end

    def run_clients
      sleep 5 until @studio.up?

      @clients.values.map(&:run)
    end

    def clean_last_run_clients
      @clients.values.map(&:clean_last_run)
    end

    def clean_last_run_machines
      @studio.clean_last_run
      clean_last_run_clients
    end

    def run_and_configure_setup
      retries ||= 0
      Filelock '/var/tmp/virthck.lock', timeout: 0 do
        @studio.run
        run_clients
      end
      configure_setup_and_synchronize
    rescue AutoHCKError => e
      synchronize_clients(exit: true)
      @project.logger.warn("Running and configuring setup failed: (#{e.class}) "\
                        "#{e.message}")
      raise e unless (retries += 1) < AUTOHCK_RETRIES

      clean_last_run_machines
      @project.setup_manager&.close
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
      loop do
        @project.logger.info('Please type "stop" to stop AutoHCK')
        break if gets.chomp == 'stop'
      end
      @project.logger.info('AutoHCK will be stopped')
    end

    def auto_run
      client = @client1
      client.run_tests
      client.create_package
    end

    def run
      upload_driver_package unless @driver_path.nil?

      @studio = @project.setup_manager.create_studio
      initialize_clients

      @project.logger.info('AutoHCK started in manual mode') if @project.options.test.manual

      run_and_configure_setup

      if @project.options.test.manual
        manual_run
      else
        auto_run
      end
    end

    def close
      @project.logger.info('Closing HCK test engine')

      @clients&.values&.map(&:abort)
      @studio&.abort
    end
  end
end
