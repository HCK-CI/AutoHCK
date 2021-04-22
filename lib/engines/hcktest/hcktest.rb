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
    attr_reader :driver, :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    DRIVERS_JSON = 'drivers.json'
    ENGINE_MODE = 'test'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{@project.tag}.log")
      @platform = read_platform
      @driver_path = @project.options.test.driver_path
      @driver = find_driver
      prepare_extra_sw
      validate_paths
      init_workspace
    end

    def prepare_extra_sw
      unless @driver['extra_software'].nil?
        @project.extra_sw_manager.prepare_software_packages(
          @driver['extra_software'], @platform['kit'], ENGINE_MODE
        )
      end

      return if @platform['extra_software'].nil?

      @project.extra_sw_manager.prepare_software_packages(
        @platform['extra_software'], @platform['kit'], ENGINE_MODE
      )
    end

    def init_workspace
      @workspace_path = [@project.workspace_path, @driver['short'],
                         @platform['name'], @project.timestamp].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @project.logger.warn('Workspace path already exists')
      end
      @project.move_workspace_to(@workspace_path.to_s)
    end

    def validate_paths
      normalize_paths
      return if File.exist?("#{@driver_path}/#{@driver['inf']}")

      @project.logger.fatal('Driver path is not valid')
      raise(InvalidPathError, "Driver path #{@driver_path}/#{@driver['inf']} is not valid")
    end

    def normalize_paths
      @driver_path.chomp!('/')
    end

    def find_driver
      drivers = @project.options.test.drivers
      if drivers.size != 1
        raise(AutoHCKError, "Wrong drivers list: #{drivers}. Currently only one driver can be tested.")
      end

      drivers_info = read_json(DRIVERS_JSON, @project.logger)
      short_name = drivers.first
      @project.logger.info("Loading driver: #{short_name}")
      res = drivers_info.find { |driver| driver['short'] == short_name }
      @project.logger.fatal("#{short_name} does not exist") unless res
      res || raise(InvalidConfigFile, "#{short_name} does not exist")
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
      @platform['clients'].each do |name, client|
        @clients[client['name']] = @project.setup_manager.create_client(name,
                                                                        client['name'])
        break unless @driver['support']
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
      @clients.values.map(&:configure)
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

      r_name = "#{@project.tag}.zip"
      zip_path = "#{@workspace_path}/#{r_name}"
      create_zip_from_directory(zip_path, @driver_path)
      @project.result_uploader.upload_file(zip_path, r_name)
    end

    def run
      upload_driver_package

      @studio = @project.setup_manager.create_studio
      initialize_clients

      run_and_configure_setup
      client = @client1
      client.run_tests
      client.create_package
    end

    def close
      @clients&.values&.map(&:abort)
      @studio&.abort
    end
  end
end
