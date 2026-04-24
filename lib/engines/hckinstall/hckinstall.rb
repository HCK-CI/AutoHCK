# typed: true
# frozen_string_literal: true

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
    KIT_JSON_DIR = 'lib/engines/hckinstall/kits'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'
    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'
    ENGINE_MODE = 'install'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.options.install.platform}.log")
      init_config
      init_class_variables
      init_iso_info
      validate_paths
      prepare_setup_scripts
      prepare_extra_sw
      @logger.debug('HCKInstall: initialized')
      @project.notification_manager.post_engine_init(self)
    end

    def test_steps
      []
    end

    def self.tag(options)
      options.install.platform
    end

    def self.platform(logger, options)
      platform_name = options.install.platform
      platform_json = "#{PLATFORMS_JSON_DIR}/#{platform_name}.json"

      logger.info("Loading platform: #{platform_name}")
      Json.read_json(platform_json, logger)
    end

    def read_iso(iso_name)
      iso = Json.read_json(ISO_JSON, @logger)
      @logger.info("Loading ISO info for: #{iso_name}")
      res = iso[iso_name]
      @logger.fatal("ISO info for #{iso_name} does not exist") unless res
      res || raise(InvalidConfigFile, "ISO info for #{iso_name} does not exist")
    end

    sig { params(kit_name: String).returns(Models::Kit) }
    def read_kit(kit_name)
      kit_json = "#{KIT_JSON_DIR}/#{kit_name}.json"

      @logger.info("Loading kit by name: #{kit_name}")
      Models::Kit.from_json_file(kit_json, @logger)
    end

    def init_config
      @config = Json.read_json(CONFIG_JSON, @logger)

      @hck_setup_scripts_path_template = Pathname.new(File.expand_path('./setup-scripts', __dir__))
      @answer_files_path_template = Pathname.new(File.expand_path('./answer-files', __dir__))
      @workspace_hlk_setup_scripts_path = Pathname.new(@project.workspace_path).join('hck-setup-scripts')

      @answer_files = @config['answer_files']
      @install_timeout = @config['install_timeout']
    end

    def prepare_setup_scripts
      @logger.info("Copying HLK setup scripts template from #{@hck_setup_scripts_path_template} to workspace")
      copy_setup_scripts_template(@workspace_hlk_setup_scripts_path, @hck_setup_scripts_path_template)
    end

    def studio_iso_name(kit)
      res = @kit_info.studio_platform
      @logger.info("Loading studio ISO name for kit: #{kit}")
      @logger.fatal("Kit studio platform for kit #{kit} does not exist") unless res
      res || raise(InvalidConfigFile, "Kit studio platform for kit #{kit} does not exist")
    end

    def init_iso_info
      studio_iso = studio_iso_name(@project.engine_platform['kit'])
      @logger.info("Studio ISO name is #{studio_iso}")
      @studio_iso_info = read_iso(studio_iso)

      client_iso = @project.engine_platform['client_iso']
      @logger.info("Client ISO name is #{client_iso}")
      @client_iso_info = read_iso(client_iso)

      @setup_studio_iso = Pathname.new(@project.workspace_path).join('setup-studio.iso')
      @setup_client_iso = Pathname.new(@project.workspace_path).join('setup-client.iso')
    end

    def init_class_variables
      @iso_path = Pathname.new(@project.config['iso_path'])
      @kit_info = read_kit(@project.engine_platform['kit'])
      @clients_name = @project.engine_platform['clients'].map { |_k, v| v['name'] }
    end

    def prepare_extra_sw
      extra_software = [*@kit_info.extra_software, *@project.engine_platform['extra_software']]

      @project.extra_sw_manager.prepare_software_packages(
        extra_software, @project.engine_platform['kit'], ENGINE_MODE
      )

      @project.extra_sw_manager.copy_to_setup_scripts(@workspace_hlk_setup_scripts_path)
    end

    def validate_paths
      normalize_paths
      studio_iso_full_path = @iso_path.join(@studio_iso_info['path'])
      unless File.exist?(studio_iso_full_path)
        @logger.fatal("Studio ISO path #{studio_iso_full_path} is not valid")
        raise(InvalidPathError, "Studio ISO path #{studio_iso_full_path} is not valid")
      end

      client_iso_full_path = @iso_path.join(@client_iso_info['path'])
      return if File.exist?(client_iso_full_path)

      @logger.fatal("Client ISO path #{client_iso_full_path} is not valid")
      raise(InvalidPathError, "Client ISO path #{client_iso_full_path} is not valid")
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

    sig { void }
    def move_downloaded_kit
      if @kit_path.end_with?('.iso')
        new_path = @iso_path.join(File.basename(@kit_path))
        @logger.info("Moving downloaded ISO from #{@kit_path} to #{new_path}")
        FileUtils.mv(@kit_path, new_path)
        @kit_path = new_path.to_s
      elsif @kit_path.end_with?('.exe')
        @logger.info('Downloaded kit is an executable, no need to move')
      end
    end

    sig { params(kit_type: String, kit_version: String).void }
    def prepare_kit_installer(kit_type, kit_version)
      @kit_path = find_kit(kit_type, kit_version)

      if @kit_path.nil?
        if @kit_info.download_url.nil?
          raise(EngineError, 'HLK installer download URL is not provided and installer is not found')
        end

        @kit_path = download_kit_installer(@kit_info.download_url, "#{kit_type}#{kit_version}",
                                           @workspace_hlk_setup_scripts_path)
        move_downloaded_kit
      else
        @logger.info("HLK installer #{kit_type}#{kit_version} already exists")
      end

      @kit_is_iso = @kit_path.end_with?('.iso')

      @logger.info("HLK installer #{kit_type}#{kit_version} was found at #{@kit_path}")
    end

    def prepare_setup_scripts_config
      kit_type, kit_version = parse_kit_info

      options_install = @project.options.install
      config = {
        kit_type:,
        hlk_kit_ver: kit_version,
        debug: options_install.debug,
        no_reboot_after_bugcheck: options_install.no_reboot_after_bugcheck
      }

      prepare_kit_installer(kit_type, kit_version)
      create_setup_scripts_config(@workspace_hlk_setup_scripts_path, config)
    end

    sig { returns([String, String]) }
    def parse_kit_info
      kit_string = @project.engine_platform['kit']
      kit_type = kit_string[0..2] || ''
      kit_version = kit_type == 'HCK' ? '' : (kit_string[3..] || '')
      [kit_type, kit_version]
    end

    sig { params(kit_type: String, kit_version: String).returns(T.nilable(String)) }
    def find_kit(kit_type, kit_version)
      installers = [
        # Disable for now because EXE installer are small and we can just redownload them
        # Also, without dedicated HLK-Setup-Scripts folder, it's unknown where exactly the installer
        # should be placed, so it's better to just redownload it if it's not an ISO
        # "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}Setup.exe",
        # "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}/#{kit_type}Setup.exe",
        # "#{@hck_setup_scripts_path}/Kits/#{kit_type}#{kit_version}Setup.iso",
        "#{@iso_path}/#{kit_type}#{kit_version}Setup.iso"
      ]

      installers.find { File.exist? _1 }
    end

    sig { params(product_key: T.nilable(String)).returns(String) }
    def product_key_xml(product_key)
      product_key == '' || product_key.nil? ? '' : "<Key>#{product_key}</Key>"
    end

    sig { params(file: String, disk_config: String).returns(Pathname) }
    def build_answer_file_path(file, disk_config)
      paths = [
        @answer_files_path_template.join("#{file}.#{disk_config}.in"),
        @answer_files_path_template.join("#{file}.in")
      ]

      paths.each do |path|
        @logger.debug("Looking for answer file at #{path}")
        return path if File.exist?(path)
      end

      raise(InvalidConfigFile, "Answer file for #{file} with disk config #{disk_config} does not exist")
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

    def create_studio_answer_files
      studio = @studio_iso_info['studio']
      if studio.nil?
        @logger.fatal('Studio ISO config is invalid, missing "studio" section')
        raise(InvalidConfigFile, 'Studio ISO config is invalid, missing "studio" section')
      end
      @logger.debug('Creating studio answer files')

      product_key = studio['product_key']
      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => studio['windows_image_names'],
        '@PRODUCT_KEY@' => product_key,
        '@PRODUCT_KEY_XML@' => product_key_xml(product_key),
        '@HOST_TYPE@' => 'studio',
        '@DEFAULT_PASSWORD@' => @project.config['windows_password']
      }
      @answer_files.each do |file|
        file_gsub(build_studio_answer_file_path(file),
                  @workspace_hlk_setup_scripts_path.join(file),
                  replacement_list)
      end
    end

    def prepare_studio_drives
      @logger.info('HCKInstall: Prepare studio drives')

      create_studio_answer_files
      create_iso(@setup_studio_iso, [@workspace_hlk_setup_scripts_path], @kit_is_iso ? ['Kits'] : [])

      @project.setup_manager.create_studio_image
    end

    def copy_drivers
      @logger.info('HCKInstall: Copy all drivers')
      FileUtils.copy_entry(@project.options.install.driver_path,
                           @workspace_hlk_setup_scripts_path.join('drivers'))
    end

    def create_client_answer_files
      client = @client_iso_info['client']
      if client.nil?
        @logger.fatal('Client ISO config is invalid, missing "client" section')
        raise(InvalidConfigFile, 'Client ISO config is invalid, missing "client" section')
      end
      @logger.debug('Creating client answer files')

      product_key = client['product_key']

      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => client['windows_image_names'],
        '@PRODUCT_KEY@' => product_key,
        '@PRODUCT_KEY_XML@' => product_key_xml(product_key),
        '@HOST_TYPE@' => 'client',
        '@DEFAULT_PASSWORD@' => @project.config['windows_password']
      }
      @answer_files.each do |file|
        file_gsub(build_client_answer_file_path(file),
                  @workspace_hlk_setup_scripts_path.join(file),
                  replacement_list)
      end
    end

    def prepare_client_drives
      @logger.info('HCKInstall: Prepare client drives')

      create_client_answer_files

      copy_drivers if @need_copy_drivers

      create_iso(@setup_client_iso, [@workspace_hlk_setup_scripts_path], ['Kits'])

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
      @project.notification_manager.pre_engine_run(self)
      @logger.debug('HCKInstall: run')

      prepare_setup_scripts_config

      studio = plan_studio
      client = plan_client

      Timeout.timeout(@install_timeout) do
        run_first(studio:, client:)
        run_second(client:)
      end
    ensure
      @project.notification_manager.post_engine_run(self)
    end
  end
end
