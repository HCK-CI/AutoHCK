# frozen_string_literal: true

module AutoHCK
  module Functest
    # TestLoader loads and validates JSON test definitions
    class TestLoader
      STEP_COLLECTIONS = %w[pre_test_commands test_steps cleanup].freeze
      SCRIPT_PATH_FIELDS = %w[guest_run_file host_run_file].freeze
      LEGACY_TEST_PATH_PREFIX = 'lib/engines/functest/tests/'

      def initialize(project, tests_path)
        @project = project
        @logger = project.logger
        @base_path = File.expand_path(tests_path)
      end

      # Load a test suite JSON file
      def load_suite(suite_name)
        suite_path = File.join(@base_path, 'suites', "#{suite_name}.json")
        raise InvalidConfigFile, "Test suite not found: #{suite_path}" unless File.exist?(suite_path)

        @logger.info("Loading test suite: #{suite_path}")
        Suite.from_json_file(suite_path, @logger)
      end

      # Load a single test case JSON file
      def load_test(test_name)
        test_path = File.join(@base_path, 'cases', "#{test_name}.json")
        raise InvalidConfigFile, "Test case not found: #{test_path}" unless File.exist?(test_path)

        @logger.info("Loading test case: #{test_path}")
        definition = AutoHCK::Helper::Json.read_json(test_path, @logger)
        resolve_test_paths(definition)
        TestCase.from_hash(definition)
      end

      # Load test cases referenced by a suite
      def load_suite_tests(suite)
        suite.tests.map { |test_name| load_test(test_name) }
      end

      private

      def resolve_test_paths(definition)
        STEP_COLLECTIONS.each do |collection|
          definition.fetch(collection, []).each { |step| resolve_step_paths(step) }
        end
      end

      def resolve_step_paths(step)
        SCRIPT_PATH_FIELDS.each { |field| resolve_config_path(step, field) }

        step.fetch('files_action', []).each do |action|
          resolve_config_path(action, 'local_path')
        end

        step.dig('parallel', 'branches')&.each_value do |branch|
          branch.each { |sub_step| resolve_step_paths(sub_step) }
        end
      end

      def resolve_config_path(config, field)
        config[field] = resolve_local_path(config[field]) if config[field]
      end

      def resolve_local_path(path)
        return path if Pathname.new(path).absolute? || dynamic_path?(path)

        relative_path = path.delete_prefix(LEGACY_TEST_PATH_PREFIX)
        File.expand_path(relative_path, @base_path)
      end

      def dynamic_path?(path)
        path.match?(/\A@[^@]+@/) || path == '~' || path.start_with?('~/')
      end
    end
  end
end
