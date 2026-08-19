# typed: true
# frozen_string_literal: true

require_relative 'test_context'
require_relative 'branch_context'
require_relative 'test_loader'
require_relative 'step_handler'
require_relative 'parallel_branch_runner'
require_relative 'test_executor'

module AutoHCK
  # Functest engine for JSON-driven functional tests
  class FunctestEngine
    extend T::Sig
    include Helper

    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'
    EXTENSIONS_JSON_DIR = 'lib/engines/hcktest/extensions'

    attr_reader :project, :logger, :drivers, :extensions, :suite

    def default_timeout
      @config['default_timeout']
    end

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.engine_tag}.log")
      @config = load_engine_config
      @drivers = load_drivers
      @tests = init_tests
      @extensions = find_extensions
      prepare_extra_sw
      @logger.info('Functest engine initialized')
    end

    def self.base_tag(options)
      platform = options.test.platform

      category = options.test.category
      return "#{category}-#{platform}" if category

      drivers = options.test.drivers
      return "#{drivers.first}-#{platform}" if drivers.length == 1

      "functest-#{platform}"
    end

    def self.tag(options)
      base_tag = base_tag(options)
      suffix = options.test.tag_suffix&.strip
      return base_tag unless suffix && !suffix.empty?

      "#{base_tag}-#{suffix}"
    end

    def self.platform(logger, options)
      platform_name = options.test.platform
      platform_json = File.join(
        File.dirname(__FILE__),
        '../hcktest/platforms',
        "#{platform_name}.json"
      )

      raise InvalidConfigFile, "Platform configuration not found: #{platform_json}" unless File.exist?(platform_json)

      Models::HLKPlatform.from_json_file(platform_json, logger)
    end

    ENGINE_MODE = 'test'

    def result_uploader_needed?
      true
    end

    def test_steps
      @executor&.test_results || []
    end

    def clients_system_info
      {}
    end

    def init_tests
      loader = Functest::TestLoader.new(@project, @config['test_definitions_path'])
      tests = load_tests(loader)
      @logger.info("Total tests to run: #{tests.length}")
      tests
    end

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/MethodLength
    def engine_setup_manager_callback(machine_name, action)
      client = @clients.find { |c| c.name == machine_name }
      raise EngineError, "No client found for machine #{machine_name}" unless client

      case action
      when Models::EngineSetupManagerActions::Shutdown
        @tools.shutdown_machine(machine_name)
      when Models::EngineSetupManagerActions::PowerOff
        client.stop_client
      when Models::EngineSetupManagerActions::PowerOn
        client.start_client
      when Models::EngineSetupManagerActions::PowerOnWait
        client.start_client(wait: true)
      when Models::EngineSetupManagerActions::Reboot
        @tools.restart_machine(machine_name)
      when Models::EngineSetupManagerActions::RebootWait
        @tools.restart_machine_and_wait(machine_name)
      when Models::EngineSetupManagerActions::WaitPowerDown
        sleep 5 while client.client_alive?
      when Models::EngineSetupManagerActions::ValidatePowerDown
        raise 'Client must be powered down, but it is online' if client.client_alive?
      when Models::EngineSetupManagerActions::ValidatePowerOn
        raise 'Client must be powered on, but it is offline' unless client.client_alive?
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize
    def run
      @logger.info('Starting functest engine')
      validate_tests_selected!

      ResourceScope.open do |scope|
        @clients = boot_clients(scope)
        raise AutoHCKError, 'No clients booted for the selected tests' if @clients.empty?

        @tools = build_tools(@clients)
        prepare_clients(@clients, @tools)
        command_execution_manager = build_command_execution_manager(@tools, @clients)

        run_context = Functest::TestExecutor::RunContext.new(
          clients: @clients,
          tools: @tools,
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
      @logger.error("Functest engine failed: #{e.message}")
      @logger.error(T.must(e.backtrace).join("\n"))
      1
    end
    # rubocop:enable Metrics/AbcSize

    private

    # Stops early with a clear error if no tests were selected. Without
    # this, boot_clients would boot zero clients and crash later.
    def validate_tests_selected!
      return unless @tests.empty?

      raise AutoHCKError, 'No tests selected to run (check --category/--testcase and ' \
                          '--select-test-names/--reject-test-names filters)'
    end

    # All client ids needed by the selected tests, combined and
    # de-duplicated, in the order first seen.
    def client_ids
      @tests.flat_map(&:clients).uniq
    end

    def boot_clients(scope)
      platform = @project.engine_platform

      client_ids.map do |client_id|
        client = platform.client_for_id(client_id)
        unless client
          raise AutoHCKError, "Test(s) require client #{client_id}, which is not declared " \
                              'in the platform configuration'
        end

        @project.setup_manager.run_functest_client(scope, client.name)
      end
    end

    # One FunctestTools instance, shared by every booted client.
    def build_tools(clients)
      clients_addrs = clients.to_h { |client| [client.name, client.winrm_addr] }
      FunctestTools.new(@project, clients_addrs)
    end

    # Gets every client ready (wait online, install software/drivers)
    def prepare_clients(clients, tools)
      threads = clients.map { |client| Thread.new { client.prepare_machine(tools) } }
      threads.each(&:join)
    end

    def build_command_execution_manager(tools, clients)
      CommandExecutionManager.new(
        project: @project,
        tools: tools,
        machines: clients.map(&:name),
        init_opts: {
          reboot_strategy: CommandExecutionManager::RebootStrategy[:WinrmPoll],
          engine_setup_manager_callback: method(:engine_setup_manager_callback)
        }
      )
    end

    def load_tests(loader)
      names, static_reject_names = test_names_and_static_rejects(loader)

      names = apply_select_test_names(names)
      names = apply_reject_test_names(names, static_reject_names)

      names.map { |test_name| loader.load_test(test_name) }
    end

    # Returns the ordered list of test names to load, plus the suite's own
    # static reject list (empty when running via --testcase, since there is
    # no suite in that case).
    def test_names_and_static_rejects(loader)
      test_options = @project.options.test
      if test_options.category
        @suite = loader.load_suite(test_options.category)
        @logger.info("Loaded test suite: #{@suite.name}")
        [@suite.tests, @suite.reject_test_names]
      elsif test_options.testcase
        [test_options.testcase.split(',').map(&:strip), []]
      else
        raise AutoHCKError, 'Functest requires --category or --testcase'
      end
    end

    # Reads a text file of test names, one per line.
    def read_test_names_file(path)
      raise AutoHCKError, "Test names file not found: #{path}" unless File.exist?(path)

      File.readlines(path, chomp: true).map(&:strip).reject(&:empty?)
    end

    # --select-test-names <file>: keep only tests whose name appears in the file,
    # preserving the original order. No-op when the option is not set.
    def apply_select_test_names(names)
      select_file = @project.options.test.select_test_names
      return names unless select_file

      select_names = read_test_names_file(select_file)
      selected = names & select_names

      @logger.info("Applying custom selected test names: #{selected.length} of #{names.length} test(s) selected")
      selected
    end

    # --reject-test-names <file> takes precedence over the suite's own static
    # reject_test_names list; if neither is present, nothing is rejected.
    def apply_reject_test_names(names, static_reject_names)
      reject_file = @project.options.test.reject_test_names
      reject_names = reject_file ? read_test_names_file(reject_file) : static_reject_names
      return names if reject_names.empty?

      remaining = names - reject_names
      rejected_count = names.length - remaining.length
      @logger.info("Applying custom rejected test names: #{rejected_count} of #{names.length} test(s) rejected") \
        if rejected_count.positive?
      remaining
    end

    # Loads Models::Driver objects for the drivers listed on the CLI, skipping
    # infrastructure devices (same filtering as hcktest).
    def load_drivers
      @project.options.test.drivers.filter_map do |short_name|
        driver = read_driver(short_name)

        if skip_driver?(driver)
          @logger.info("Skipping driver installation for #{driver.name} (infrastructure device)")
          next
        end

        driver
      end
    end

    sig { params(short_name: String).returns(Models::Driver) }
    def read_driver(short_name)
      driver_json = "#{DRIVERS_JSON_DIR}/#{short_name}.json"

      @logger.info("Loading driver: #{short_name}")
      driver = Models::Driver.from_json_file(driver_json, @logger)
      driver.short = short_name
      driver
    end

    sig { params(driver: Models::Driver).returns(T::Boolean) }
    def skip_driver?(driver)
      return true if driver.device == @project.options.test.boot_device
      return true if driver.device == @project.options.common.client_ctrl_net_dev
      return true if driver.device == @project.engine_platform.clients_options.ctrl_net_device

      false
    end

    def prepare_extra_sw
      extra_softwares = @drivers.flat_map(&:extra_software)
      extra_softwares += @extensions.flat_map(&:extra_software)
      extra_softwares += @project.engine_platform.extra_software
      extra_softwares += @suite.requirements.extra_software if @suite
      extra_softwares += @tests.flat_map(&:extra_software)

      @project.extra_sw_manager.prepare_software_packages(
        extra_softwares, @project.engine_platform.kit, ENGINE_MODE
      )
    end

    # Populates the shared TestContext with driver-related variables so that
    # generic test JSON files can use @driver_module@, @driver_inf@, etc.
    def setup_test_context(context)
      driver_path = @project.options.test.driver_path
      context.set_variable('driver_path', driver_path) if driver_path

      test_binaries_path = @project.options.test.test_binaries_path
      context.set_variable('test_binaries_path', test_binaries_path) if test_binaries_path

      set_driver_context_variables(context, @drivers.first)
      apply_platform_context_variables(context)

      @project.options.test.test_params.each do |key, value|
        context.set_variable(key, value)
      end
    end

    def apply_platform_context_variables(context)
      client = @project.engine_platform.clients.values.first
      return unless client&.memory_gb

      context.set_variable('vm_memory_gb', client.memory_gb.to_s)
    end

    def set_driver_context_variables(context, drv)
      return unless drv

      context.set_variable('driver_name', drv.name)

      unless drv.inf
        @logger.info("Driver #{drv.name} has no package (device-only); skipping driver_inf/driver_module")
        return
      end

      module_name = drv.inf.sub(/\.inf$/i, '')
      context.set_variable('driver_inf', drv.inf)
      context.set_variable('driver_module', module_name)

      @logger.info("Test context: driver_module=#{module_name}, driver_inf=#{drv.inf}")
    end

    def find_extensions
      @project.options.test.extensions.map do |ext_name|
        @logger.info("Loading functest extension: #{ext_name}")
        path = File.join(EXTENSIONS_JSON_DIR, "#{File.basename(ext_name)}.json")
        Models::Extension.from_json_file(path, @logger)
      end
    end

    def load_engine_config
      config_path = File.join(File.dirname(__FILE__), 'functest.json')
      JSON.parse(File.read(config_path))
    rescue StandardError => e
      raise InvalidConfigFile, "Failed to load engine config: #{e.message}"
    end

    def generate_results(summary)
      @logger.info('Generating test results...')

      results_path = File.join(@project.workspace_path, 'functest_results.json')
      File.write(results_path, JSON.pretty_generate(summary))
      @logger.info("Results written to: #{results_path}")

      @project.result_uploader&.upload_file(results_path, 'functest_results.json')
    end

    def pause_run_if_needed(summary = nil, exception = nil)
      test_options = @project.options.test

      auto_manual_need = test_options.auto_manual &&
                         (!exception.nil? || (summary && summary[:failed].positive?))

      @logger.debug("Switch to manual mode check: manual=#{test_options.manual} auto_manual_need=#{auto_manual_need}")
      return unless test_options.manual || auto_manual_need

      pause_run
    end

    def pause_run
      @project.logger.info('AutoHCK switched in manual mode. Waiting for manual exit.')
      @project.logger.info("Type 'exit' and press ENTER to exit manual mode")

      # rubocop:disable Lint/Debugger
      binding.irb
      # rubocop:enable Lint/Debugger

      @project.logger.info('Manual exit. AutoHCK will continue.')
    end
  end
end
