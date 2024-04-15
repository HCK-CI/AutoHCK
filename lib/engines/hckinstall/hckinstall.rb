# typed: true
# frozen_string_literal: true

require 'uri'

require './lib/setupmanagers/hckclient'
require './lib/setupmanagers/hckstudio'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/auxiliary/iso_helper'
require './lib/auxiliary/resource_scope'
require './lib/engines/hckinstall/setup_scripts_helper'

require './lib/models/driver'

# AutoHCK module
module AutoHCK
  # HCKInstall class
  class HCKInstall
    extend T::Sig
    include Helper

    attr_reader :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    CONFIG_JSON = 'lib/engines/hckinstall/hckinstall.json'
    ISO_JSON = 'lib/engines/hckinstall/iso.json'
    KIT_JSON = 'lib/engines/hckinstall/kit.json'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'
    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'
    ENGINE_MODE = 'install'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.options.install.platform}.log")
      init_workspace
      init_config
      init_class_variables
      prepare_extra_sw
      @logger.debug('HCKInstall: initialized')
    end

    def init_workspace
      @workspace_path = [@project.workspace_path, @project.options.install.platform,
                         @project.timestamp].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @project.logger.warn('Workspace path already exists')
      end
      @project.move_workspace_to(@workspace_path.to_s)
    end

    def read_platform
      platform_name = @project.options.install.platform
      platform_json = "#{PLATFORMS_JSON_DIR}/#{platform_name}.json"

      @logger.info("Loading platform: #{platform_name}")
      unless File.exist?(platform_json)
        @logger.fatal("#{platform_name} does not exist")
        raise(InvalidConfigFile, "#{platform_name} does not exist")
      end

      Json.read_json(platform_json, @logger)
    end

    def read_iso(platform_name)
      iso = Json.read_json(ISO_JSON, @logger)
      @logger.info("Loading ISO for platform: #{platform_name}")
      res = iso[platform_name]
      @logger.fatal("ISO info for #{platform_name} does not exist") unless res
      res || raise(InvalidConfigFile, "ISO info for #{platform_name} does not exist")
    end

    def read_kit(kit_name)
      kit_list = Json.read_json(KIT_JSON, @logger)
      @logger.info("Loading kit by name: #{kit_name}")
      res = kit_list[kit_name]
      @logger.fatal("Kit info with name #{kit_name} does not exist") unless res
      res || raise(InvalidConfigFile, "Kit info with name #{kit_name} does not exist")
    end

    def init_config
      @config = Json.read_json(CONFIG_JSON, @logger)

      @hck_setup_scripts_path = @config['hck_setup_scripts_path']

      @answer_files = @config['answer_files']
      @install_timeout = @config['install_timeout']
    end

    def studio_platform(kit)
      res = @kit_info['studio_platform']
      @logger.info("Loading studio platform for kit: #{kit}")
      @logger.fatal("Kit studio platform for kit #{kit} does not exist") unless res
      res || raise(InvalidConfigFile, "Kit studio platform for kit #{kit} does not exist")
    end

    def client_platform
      @platform['clients'].values.first['image'][/Win\w+x(86|64)/]
    end

    def init_class_variables
      @iso_path = @project.config['iso_path']

      @platform = read_platform
      @kit_info = read_kit(@platform['kit'])

      @clients_name = @platform['clients'].map { |_k, v| v['name'] }

      @studio_iso_info = read_iso(studio_platform(@platform['kit']))
      @client_iso_info = read_iso(client_platform)

      validate_paths

      @setup_studio_iso = "#{@workspace_path}/setup-studio.iso"
      @setup_client_iso = "#{@workspace_path}/setup-client.iso"
    end

    def prepare_extra_sw
      unless @kit_info['extra_software'].nil?
        @project.extra_sw_manager.prepare_software_packages(
          @kit_info['extra_software'], @platform['kit'], ENGINE_MODE
        )
      end

      unless @platform['extra_software'].nil?
        @project.extra_sw_manager.prepare_software_packages(
          @platform['extra_software'], @platform['kit'], ENGINE_MODE
        )
      end

      @project.extra_sw_manager.copy_to_setup_scripts(@hck_setup_scripts_path)
    end

    def validate_paths
      normalize_paths
      unless File.exist?("#{@iso_path}/#{@studio_iso_info['path']}")
        @logger.fatal('Studio ISO path is not valid')
        raise(InvalidPathError, 'Studio ISO path is not valid')
      end

      return if File.exist?("#{@iso_path}/#{@client_iso_info['path']}")

      @logger.fatal('Client ISO path is not valid')
      raise(InvalidPathError, 'Client ISO path is not valid')
    end

    def normalize_paths
      @studio_iso_info['path'].chomp!('/')
      @client_iso_info['path'].chomp!('/')
    end

    sig { params(driver: String).returns(Models::Driver) }
    def read_driver(driver)
      driver_json = "#{DRIVERS_JSON_DIR}/#{driver}.json"

      @logger.info("Loading driver: #{driver}")
      Models::Driver.from_json_file(driver_json, @logger)
    end

    sig { returns(T::Array[Models::Driver]) }
    def find_drivers
      @project.options.install.drivers.map do |short_name|
        driver = read_driver(short_name)

        driver.short = short_name

        driver
      end
    end

    sig { returns(T::Array[Models::Driver]) }
    def drivers
      drivers = find_drivers

      @need_copy_drivers = false
      drivers.each do |driver|
        next if driver.install_method == Models::DriverInstallMethods::NoDrviver

        if driver.install_method == Models::DriverInstallMethods::PNP &&
           File.exist?("#{@project.options.install.driver_path}/#{driver.inf}")
          @need_copy_drivers = true
          next
        end

        msg = "Can't install #{driver.short} driver for device #{driver.device} in install mode"
        @project.logger.fatal(msg)
        raise(InvalidConfigFile, msg)
      end

      drivers
    end

    def handle_cancel
      return false
    end

    def target
      nil
    end

    def result_uploader_needed?
      true
    end

    def run_studio(scope, iso_list = [], keep_alive:, snapshot: true)
      st_opts = {
        keep_alive:,
        create_snapshot: snapshot,
        attach_iso_list: iso_list,
        secure: true
      }

      @project.setup_manager.run_studio(scope, st_opts)
    end

    def run_client(scope, name, snapshot: true, secure: true)
      cl_opts = {
        create_snapshot: snapshot,
        attach_iso_list: [
          @setup_client_iso,
          @client_iso_info['path']
        ],
        secure:
      }

      @project.setup_manager.run_client(scope, name, cl_opts)
    end

    def wait_vms(vms)
      vms.each do |name, vm|
        @logger.info("Waiting for #{name} to finish")
        vm.wait
      end
    end

    def run_first(studio:, client:)
      ResourceScope.open do |scope|
        vms = []

        if studio
          prepare_studio_drives

          iso_list = [@setup_studio_iso, @studio_iso_info['path']]
          iso_list << @kit_path if @kit_is_iso
          vms << [
            'studio',
            run_studio(scope, iso_list, keep_alive: false, snapshot: false)
          ]
        end

        if client
          prepare_client_drives

          @clients_name.each do |c|
            vms << [c, run_client(scope, c, snapshot: false)]
          end
        end

        wait_vms vms
      end
    end

    def run_second(client:)
      return unless client

      ResourceScope.open do |scope|
        run_studio(scope, [], keep_alive: true)

        cl = @clients_name.map do |c|
          [c, run_client(scope, c, snapshot: false, secure: false)]
        end

        wait_vms cl
      end
    end

    def prepare_setup_scripts_config
      kit_type, kit_version = parse_kit_info

      config = {
        kit_type:,
        hlk_kit_ver: kit_version
      }

      @kit_path = find_kit(kit_type, kit_version)

      if @kit_path.nil?
        if @kit_info['download_url'].nil?
          raise(EngineError, 'HLK installer download URL is not provided and installer is not found')
        end

        @kit_path = download_kit_installer(@kit_info['download_url'],
                                           "#{kit_type}#{kit_version}", @hck_setup_scripts_path)
      else
        @logger.info("HLK installer #{kit_type}#{kit_version} already exists")
      end

      @kit_is_iso = @kit_path.end_with?('.iso')

      @logger.info("HLK installer #{kit_type}#{kit_version} was found at #{@kit_path}")

      create_setup_scripts_config(@hck_setup_scripts_path, config)
    end

    def parse_kit_info
      kit_string = @platform['kit']
      kit_type = kit_string[0..2]
      kit_version = kit_type == 'HCK' ? '' : kit_string[3..]
      [kit_type, kit_version]
    end

    def find_kit(kit_type, kit_version)
      installers = [
        "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}Setup.exe",
        "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}/#{kit_type}Setup.exe",
        "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}Setup.iso"
      ]

      installers.find { File.exist? _1 }
    end

    def product_key_xml(product_key)
      product_key == '' || product_key.nil? ? '' : "<Key>#{product_key}</Key>"
    end

    def build_answer_file_path(file, disk_config)
      paths = [
        @hck_setup_scripts_path + "/answer-files/#{file}.#{disk_config}.in",
        @hck_setup_scripts_path + "/answer-files/#{file}.in"
      ]

      paths.each do |path|
        return path if File.exist?(path)
      end
    end

    def load_fw_disk_config(fw_type)
      fws = Json.read_json(FW_JSON, @logger)
      @logger.info("Loading FW: #{fw_type}")
      res = fws[fw_type]

      unless res
        @logger.fatal("#{@fw_name} does not exist")
        raise(InvalidConfigFile, "#{@fw_name} does not exist")
      end

      res['disk_config']
    end

    def build_studio_answer_file_path(file)
      fw_type = @project.setup_manager.studio_option_config('fw_type')

      disk_config = load_fw_disk_config(fw_type)

      build_answer_file_path(file, disk_config)
    end

    def build_client_answer_file_path(file)
      fw_type = @project.setup_manager.client_option_config(@clients_name.first, 'fw_type')

      disk_config = load_fw_disk_config(fw_type)

      build_answer_file_path(file, disk_config)
    end

    def prepare_studio_drives
      product_key = @studio_iso_info.dig('studio', 'product_key')

      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => @studio_iso_info['studio']['windows_image_names'],
        '@PRODUCT_KEY@' => product_key,
        '@PRODUCT_KEY_XML@' => product_key_xml(product_key),
        '@HOST_TYPE@' => 'studio'
      }
      @answer_files.each do |file|
        file_gsub(build_studio_answer_file_path(file),
                  @hck_setup_scripts_path + "/#{file}", replacement_list)
      end

      create_iso(@setup_studio_iso, [@hck_setup_scripts_path], @kit_is_iso ? ['Kits'] : [])

      @project.setup_manager.create_studio_image
    end

    def copy_drivers
      @logger.info('HCKInstall: Copy all drivers')
      FileUtils.rm_rf("#{@hck_setup_scripts_path}/drivers")
      FileUtils.copy_entry(@project.options.install.driver_path,
                           "#{@hck_setup_scripts_path}/drivers")
    end

    def prepare_client_drives
      product_key = @client_iso_info.dig('client', 'product_key')

      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => @client_iso_info['client']['windows_image_names'],
        '@PRODUCT_KEY@' => product_key,
        '@PRODUCT_KEY_XML@' => product_key_xml(product_key),
        '@HOST_TYPE@' => 'client'
      }
      @answer_files.each do |file|
        file_gsub(build_client_answer_file_path(file),
                  @hck_setup_scripts_path + "/#{file}", replacement_list)
      end

      copy_drivers if @need_copy_drivers

      create_iso(@setup_client_iso, [@hck_setup_scripts_path], ['Kits'])

      @clients_name.each { @project.setup_manager.create_client_image(_1) }
    end

    def tag
      "install-#{@project.options.install.platform}"
    end

    def plan_studio
      return true unless @project.setup_manager.check_studio_image_exist

      if @project.options.install.force
        @logger.info('HCKInstall: Studio image exist, force reinstall started')
        return true
      end

      @logger.info('HCKInstall: Studio image exist, installation skipped')
      false
    end

    def plan_client
      !@project.options.install.skip_client
    end

    def run
      @logger.debug('HCKInstall: run')

      prepare_setup_scripts_config

      studio = plan_studio
      client = plan_client

      Timeout.timeout(@install_timeout) do
        run_first(studio:, client:)
        run_second(client:)
      end
    end
  end
end
