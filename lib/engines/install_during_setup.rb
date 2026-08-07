# typed: false
# frozen_string_literal: true

module AutoHCK
  # Shared logic for engines that install Windows unattended with drivers
  # injected during setup (the answer-file DriverPaths / d:\drivers\ mechanism).
  #
  # Mixed into both HCKInstall and InstallTestEngine. The answer-file templates
  # are owned by the hckinstall engine and reused from here, so there is a
  # single source of truth and the UEFI and BIOS variants stay in sync across
  # both engines.
  #
  # Includers must:
  #   * include Helper (for #file_gsub)
  #   * define #setup_scripts_workspace -> Pathname of the workspace
  #     setup-scripts directory the rendered answer files are written into
  #   * set @project, @logger, @client_iso_infos and @answer_files before
  #     calling #create_client_answer_files
  module InstallDuringSetup
    extend T::Sig

    ISO_JSON = 'lib/engines/hckinstall/iso.json'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'

    def read_iso(iso_name)
      iso = Helper::Json.read_json(ISO_JSON, @logger)
      @logger.info("Loading ISO info for: #{iso_name}")
      res = iso[iso_name]
      @logger.fatal("ISO info for #{iso_name} does not exist") unless res
      res || raise(InvalidConfigFile, "ISO info for #{iso_name} does not exist")
    end

    sig { params(product_key: T.nilable(String)).returns(String) }
    def product_key_xml(product_key)
      product_key == '' || product_key.nil? ? '' : "<Key>#{product_key}</Key>"
    end

    def load_fw_disk_config(fw_type)
      fws = Helper::Json.read_json(FW_JSON, @logger)
      @logger.info("Loading FW: #{fw_type}")
      res = fws[fw_type]
      raise(InvalidConfigFile, "Firmware type #{fw_type} does not exist in #{FW_JSON}") unless res

      res['disk_config']
    end

    # Answer-file templates live in the hckinstall engine and are shared here.
    def answer_files_template_path
      @answer_files_template_path ||=
        Pathname.new(File.expand_path('hckinstall/answer-files', __dir__))
    end

    sig { params(file: String, disk_config: String).returns(Pathname) }
    def build_answer_file_path(file, disk_config)
      paths = [
        answer_files_template_path.join("#{file}.#{disk_config}.in"),
        answer_files_template_path.join("#{file}.in")
      ]

      paths.each do |path|
        @logger.debug("Looking for answer file at #{path}")
        return path if File.exist?(path)
      end

      raise(InvalidConfigFile, "Answer file for #{file} with disk config #{disk_config} does not exist")
    end

    def build_client_answer_file_path(file, client_name)
      fw_type = @project.setup_manager.client_option_config(client_name, 'fw_type')
      disk_config = load_fw_disk_config(fw_type)

      build_answer_file_path(file, disk_config)
    end

    def client_platform_arch(client_name)
      client = @project.engine_platform.clients.values.find { |c| c.name == client_name }
      client&.arch || @project.engine_platform.client_arch || Project::DEFAULT_ARCH
    end

    def create_client_answer_files(client_name)
      client = @client_iso_infos[client_name]['client']
      if client.nil?
        @logger.fatal('Client ISO config is invalid, missing "client" section')
        raise(InvalidConfigFile, 'Client ISO config is invalid, missing "client" section')
      end
      @logger.debug("Creating client answer files for #{client_name}")

      replacement_list = client_replacement_list(client, client_name)
      @answer_files.each do |file|
        file_gsub(build_client_answer_file_path(file, client_name),
                  setup_scripts_workspace.join(file),
                  replacement_list)
      end
    end

    def client_replacement_list(client, client_name)
      product_key = client['product_key']
      {
        '@WINDOWS_IMAGE_NAME@' => client['windows_image_names'],
        '@PRODUCT_KEY@' => product_key,
        '@PRODUCT_KEY_XML@' => product_key_xml(product_key),
        '@HOST_TYPE@' => 'client',
        '@DEFAULT_PASSWORD@' => @project.config['windows_password'],
        '@PROCESSOR_ARCHITECTURE@' => client_platform_arch(client_name)
      }
    end
  end
end
