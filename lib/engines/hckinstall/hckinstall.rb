# frozen_string_literal: true

require 'uri'

require './lib/setupmanagers/hckclient'
require './lib/setupmanagers/hckstudio'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/auxiliary/iso_helper'
require './lib/engines/hckinstall/setup_scripts_helper'

# AutoHCK module
module AutoHCK
  # HCKInstall class
  class HCKInstall
    include Helper

    attr_reader :platform

    PLATFORMS_JSON_DIR = 'lib/engines/hcktest/platforms'
    CONFIG_JSON = 'lib/engines/hckinstall/hckinstall.json'
    ISO_JSON = 'lib/engines/hckinstall/iso.json'
    KIT_JSON = 'lib/engines/hckinstall/kit.json'
    STUDIO_PLATFORM_JSON = 'lib/engines/hckinstall/studio_platform.json'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'
    DRIVERS_JSON = 'drivers.json'
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
      @studio_install_timeout = @config['studio_install_timeout']
      @client_install_timeout = @config['client_install_timeout']
    end

    def studio_platform(kit)
      studio_platform_list = Json.read_json(STUDIO_PLATFORM_JSON, @logger)
      @logger.info("Loading studio platform for kit: #{kit}")
      res = studio_platform_list[kit]
      @logger.fatal("Kit studio platform for kit #{kit} does not exist") unless res
      res || raise(InvalidConfigFile, "Kit studio platform for kit #{kit} does not exist")
    end

    def client_platform
      @platform['clients'].values.first['image'][/Win\w+x(86|64)/]
    end

    def init_class_variables
      @iso_path = @project.config['iso_path']

      @platform = read_platform
      @clients_name = @platform['clients'].map { |_k, v| v['name'] }

      @studio_iso_info = read_iso(studio_platform(@platform['kit']))
      @client_iso_info = read_iso(client_platform)

      @kit_info = read_kit(@platform['kit'])
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

    def find_drivers
      drivers_info = Json.read_json(DRIVERS_JSON, @project.logger)

      @project.options.install.drivers.map do |short_name|
        @project.logger.info("Loading driver: #{short_name}")
        driver = drivers_info[short_name]

        unless driver
          @project.logger.fatal("#{short_name} does not exist")
          raise(InvalidConfigFile, "#{short_name} does not exist")
        end

        driver['short'] = short_name
        driver
      end
    end

    def drivers
      drivers = find_drivers

      drivers.each do |driver|
        next if driver['install_method'] == 'no-drv'

        msg = "Can't install #{driver['short']} driver for device #{driver['device']} in install mode"
        @project.logger.fatal(msg)
        raise(InvalidConfigFile, msg)
      end

      drivers
    end

    def target
      nil
    end

    def result_uploader_needed?
      true
    end

    def run_studio(iso_list = [], snapshot: true)
      st_opts = {
        create_snapshot: snapshot,
        attach_iso_list: iso_list
      }

      st = @project.setup_manager.create_studio
      st.run(st_opts)
      st
    end

    def run_client(name, snapshot: true)
      cl_opts = {
        create_snapshot: snapshot,
        attach_iso_list: [
          @setup_client_iso,
          @client_iso_info['path']
        ]
      }

      cl = @project.setup_manager.create_client(name)
      cl.run(cl_opts)
      cl
    end

    def run_studio_installer
      @project.setup_manager.create_studio_image

      st = run_studio([
                        @setup_studio_iso,
                        @studio_iso_info['path']
                      ], snapshot: false)
      begin
        Timeout.timeout(@studio_install_timeout) do
          @logger.info('Waiting for studio installation finished')
          sleep 5 while st.alive?
        end
      ensure
        st.clean_last_run
      end
    end

    def run_client_installer(name)
      @project.setup_manager.create_client_image(name)

      run_client(name, snapshot: false)
    end

    def run_clients_installer
      st = run_studio
      begin
        cl = @clients_name.map { |c| run_client_installer(c) }
        begin
          Timeout.timeout(@client_install_timeout) do
            cl.each do |client|
              @logger.info("Waiting for #{client.name} installation finished")
              while client.alive?
                @project.setup_manager.keep_studio_alive
                sleep 5
              end
            end
          end
        ensure
          cl.each(&:clean_last_run)
        end
      ensure
        st.clean_last_run
      end
    end

    def prepare_setup_scripts_config
      kit_string = @platform['kit']
      kit_type = kit_string[0..2]
      kit_version = ''
      kit_type == 'HCK' || kit_version = kit_string[3..]

      config = {
        kit_type: kit_type,
        hlk_kit_ver: kit_version
      }

      unless @kit_info['download_url'].nil?
        download_kit_installer(@kit_info['download_url'],
                               "#{kit_type}#{kit_version}", @hck_setup_scripts_path)
      end

      installers = [
        "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}Setup.exe",
        "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}/#{kit_type}Setup.exe"
      ]

      raise unless (file = installers.find { File.exist? _1 })

      @logger.info("HLK installer #{file} was found")

      create_setup_scripts_config(@hck_setup_scripts_path, config)
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

    def prepare_studio_installer
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
      create_iso(@setup_studio_iso, [@hck_setup_scripts_path])
    end

    def prepare_client_installer
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
      create_iso(@setup_client_iso, [@hck_setup_scripts_path], ['Kits'])
    end

    def tag
      "install-#{@project.options.install.platform}"
    end

    def install_studio
      if @project.setup_manager.check_studio_image_exist
        if @project.options.install.force
          @logger.info('HCKInstall: Studio image exist, force reinstall started')

          prepare_studio_installer
          run_studio_installer
        else
          @logger.info('HCKInstall: Studio image exist, installation skipped')
        end
      else
        prepare_studio_installer
        run_studio_installer
      end
    end

    def install_clients
      if @project.options.install.skip_client
        @logger.info('HCKInstall: Client image installation skipped')
        return
      end

      prepare_client_installer
      run_clients_installer
    end

    def run
      @logger.debug('HCKInstall: run')

      prepare_setup_scripts_config

      install_studio
      install_clients
    end
  end
end
