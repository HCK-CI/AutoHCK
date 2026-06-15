# typed: true
# frozen_string_literal: true

require_relative 'test_context'
require_relative 'test_loader'
require_relative 'step_handler'
require_relative 'test_executor'

module AutoHCK
  # Functest engine for JSON-driven functional tests
  class FunctestEngine
    extend T::Sig
    include Helper

    DRIVERS_JSON_DIR = 'lib/engines/hcktest/drivers'

    attr_reader :project, :logger, :drivers

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.engine_tag}.log")
      @config = load_engine_config
      @drivers = load_drivers
      prepare_extra_sw
      @logger.info('Functest engine initialized')
    end

    def self.tag(options)
      platform = options.test.platform
      drivers = options.test.drivers
      drivers.empty? ? "functest-#{platform}" : "#{drivers.join('-')}-#{platform}"
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

    # rubocop:disable Metrics/AbcSize
    def run
      @logger.info('Starting functest engine')

      loader = Functest::TestLoader.new(@project, @config['test_definitions_path'])
      tests = load_tests(loader)
      @logger.info("Total tests to run: #{tests.length}")

      ResourceScope.open do |scope|
        client = @project.setup_manager.run_functest_client(scope, client_name)
        client.prepare_machine

        @executor = Functest::TestExecutor.new(@project, client.tools, client.name,
                                               default_timeout: @config['default_timeout'])
        setup_test_context(@executor.context)
        summary = @executor.execute_tests(tests)

        generate_results(summary)
        summary[:failed].zero? ? 0 : 1
      end
    rescue StandardError => e
      @logger.error("Functest engine failed: #{e.message}")
      @logger.error(T.must(e.backtrace).join("\n"))
      1
    end
    # rubocop:enable Metrics/AbcSize

    private

    def client_name
      name = @project.engine_platform.clients.values.first&.name
      raise AutoHCKError, 'No client found in platform configuration' unless name

      name
    end

    def load_tests(loader)
      test_options = @project.options.test
      if test_options.category
        suite = loader.load_suite(test_options.category)
        @logger.info("Loaded test suite: #{suite.name}")
        loader.load_suite_tests(suite)
      elsif test_options.testcase
        test_options.testcase.split(',').map do |test_name|
          loader.load_test(test_name.strip)
        end
      else
        raise AutoHCKError, 'Functest requires --category or --testcase'
      end
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
      extra_softwares += @project.engine_platform.extra_software

      @project.extra_sw_manager.prepare_software_packages(
        extra_softwares, @project.engine_platform.kit, ENGINE_MODE
      )
    end

    # Populates the shared TestContext with driver-related variables so that
    # generic test JSON files can use @driver_module@, @driver_inf@, etc.
    def setup_test_context(context)
      driver_path = @project.options.test.driver_path
      context.set_variable('driver_path', driver_path) if driver_path

      set_driver_context_variables(context, @drivers.first)
    end

    def set_driver_context_variables(context, drv)
      return unless drv

      module_name = drv.inf.sub(/\.inf$/i, '')
      context.set_variable('driver_inf', drv.inf)
      context.set_variable('driver_module', module_name)
      context.set_variable('driver_name', drv.name)

      @logger.info("Test context: driver_module=#{module_name}, driver_inf=#{drv.inf}")
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
  end
end
