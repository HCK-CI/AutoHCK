# typed: true
# frozen_string_literal: true

module AutoHCK
  class InstallTestEngine < FunctestEngine
    extend T::Sig
    include Helper
    include InstallDuringSetup

    def initialize(project)
      super
      init_install_config
      @logger.info('InstallTest engine initialized')
    end

    # Workspace directory the shared InstallDuringSetup helpers render answer
    # files into.
    def setup_scripts_workspace
      @workspace_setup_scripts_path
    end

    def self.base_tag(options)
      platform = options.test.platform
      category = options.test.category
      drivers = options.test.drivers

      prefix = if category
                 category
               elsif drivers.length == 1
                 drivers.first
               else
                 'installtest'
               end

      "installtest-#{prefix}-#{platform}"
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def run
      @logger.info('Starting installtest engine')
      validate_tests_selected!

      @logger.info('=== Phase 1: Fresh Windows installation with driver ===')
      Timeout.timeout(@install_timeout) do
        prepare_install_drives
        run_install
      end

      @logger.info('=== Phase 2: Boot installed image and verify driver ===')
      ResourceScope.open do |scope|
        clients = boot_installed_clients(scope)
        raise AutoHCKError, 'No clients booted for verification' if clients.empty?

        tools = build_tools(clients)
        prepare_clients(clients, tools)

        command_execution_manager = build_command_execution_manager(tools, clients)
        run_context = Functest::TestExecutor::RunContext.new(
          clients: clients,
          tools: tools,
          command_execution_manager: command_execution_manager
        )
        @executor = Functest::TestExecutor.new(self, run_context)
        setup_test_context(@executor.context)
        summary = @executor.execute_tests(@tests)

        pause_run_if_needed(summary)
        generate_results(summary)
        summary[:failed].zero? ? 0 : 1
      rescue StandardError => e
        pause_run_if_needed(nil, e)
        raise
      end
    rescue StandardError => e
      @logger.error("InstallTest engine failed: #{e.message}")
      @logger.error(T.must(e.backtrace).join("\n"))
      1
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    def load_engine_config
      config_path = File.join(File.dirname(__FILE__), 'installtest.json')
      JSON.parse(File.read(config_path))
    rescue StandardError => e
      raise InvalidConfigFile, "Failed to load installtest engine config: #{e.message}"
    end

    def init_install_config
      @iso_path = Pathname.new(@project.config['iso_path'])
      @clients_name = @project.engine_platform.clients.values.map(&:name)

      init_client_iso_info
      init_workspace_paths

      @answer_files = @config['answer_files']
      @install_timeout = @config['install_timeout']
    end

    def init_client_iso_info
      @client_iso_infos = {}
      @setup_client_isos = {}
      fallback_iso = @project.engine_platform.client_iso

      @project.engine_platform.clients.each_value do |client|
        iso_name = client.client_iso || fallback_iso
        client_name = client.name

        @logger.info("Client ISO name for #{client_name} is #{iso_name}")
        @client_iso_infos[client_name] = read_iso(iso_name)
        @setup_client_isos[client_name] = workspace_path.join("setup-client-#{client_name}.iso")
      end

      validate_client_iso_paths
    end

    def validate_client_iso_paths
      @client_iso_infos.each do |name, info|
        info['path'].chomp!('/')
        full_path = @iso_path.join(info['path'])
        next if File.exist?(full_path)

        raise(InvalidPathError, "Client ISO path #{full_path} for #{name} is not valid")
      end
    end

    def init_workspace_paths
      @workspace_setup_scripts_path = workspace_path.join('installtest-setup-scripts')
      @hckinstall_setup_scripts_template = Pathname.new(
        File.expand_path('../hckinstall/setup-scripts', __dir__)
      )
      @installtest_setup_scripts_path = Pathname.new(
        File.expand_path('./setup-scripts', __dir__)
      )
    end

    def workspace_path
      @workspace_path ||= Pathname.new(@project.workspace_path)
    end

    def install_image_path(client_name)
      workspace_path.join("install-#{client_name}.qcow2")
    end

    def prepare_install_drives
      @logger.info('InstallTest: Preparing install drives')

      prepare_setup_scripts
      copy_drivers_to_workspace
      prepare_setup_scripts_config

      @install_image_paths = {}
      @clients_name.each do |client_name|
        create_client_answer_files(client_name)
        create_iso(@setup_client_isos[client_name], [@workspace_setup_scripts_path], [])
        path = install_image_path(client_name)
        @project.setup_manager.create_client_image_at(client_name, path)
        @install_image_paths[client_name] = path
      end
    end

    def prepare_setup_scripts
      @logger.info("Copying setup scripts template from #{@hckinstall_setup_scripts_template}")
      copy_setup_scripts_template(@workspace_setup_scripts_path, @hckinstall_setup_scripts_template)

      FileUtils.mkdir_p(@workspace_setup_scripts_path.join('extra-software'))
      @logger.info('Overlaying installtest-specific client.ps1')
      FileUtils.cp(
        @installtest_setup_scripts_path.join('client.ps1'),
        @workspace_setup_scripts_path.join('client.ps1')
      )
    end

    def copy_drivers_to_workspace
      driver_path = @project.options.test.driver_path
      # Installing the driver during Windows setup is the whole point of this
      # engine, so a missing driver path must be a hard error rather than a
      # silent driver-less install.
      raise AutoHCKError, '--driver-path is required for the installtest engine' if driver_path.nil?
      raise InvalidPathError, "Driver path #{driver_path} does not exist" unless File.exist?(driver_path)

      @logger.info('InstallTest: Copying drivers to setup scripts workspace')
      FileUtils.copy_entry(driver_path, @workspace_setup_scripts_path.join('drivers'))
    end

    def prepare_setup_scripts_config
      config = {
        kit_type: '',
        hlk_kit_ver: '',
        debug: false,
        no_reboot_after_bugcheck: false,
        vmnames: ['STUDIO'] + @clients_name.map(&:upcase)
      }
      create_setup_scripts_config(@workspace_setup_scripts_path, config)
    end

    def run_install
      @logger.info('InstallTest: Running fresh Windows installation')

      ResourceScope.open do |scope|
        vms = @clients_name.map do |client_name|
          # ISO order is significant: the setup ISO (carrying drivers/) must
          # come first so it maps to D: in WinPE, matching the <Path>d:\drivers\</Path>
          # DriverPaths directive in the answer files. Do not prepend ISOs here.
          cl_opts = {
            create_snapshot: false,
            boot_image_override: @install_image_paths[client_name],
            attach_iso_list: [
              @setup_client_isos[client_name],
              @client_iso_infos[client_name]['path']
            ]
          }
          vm = @project.setup_manager.run_client(scope, client_name, cl_opts)
          [client_name, vm]
        end

        vms.each do |name, vm|
          @logger.info("Waiting for #{name} to finish Windows installation...")
          vm.wait
        end
      end

      @logger.info('InstallTest: Windows installation phase complete')
    end

    def boot_installed_clients(scope)
      @project.engine_platform.clients.each_value.map do |client_info|
        run_opts = {
          create_snapshot: true,
          boot_image_override: @install_image_paths[client_info.name]
        }
        @project.setup_manager.run_installtest_client(scope, client_info.name, run_opts)
      end
    end
  end
end
