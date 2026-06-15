# frozen_string_literal: true

module AutoHCK
  module Functest
    # TestLoader loads and validates JSON test definitions
    class TestLoader
      def initialize(project, tests_path)
        @project = project
        @logger = project.logger
        @base_path = tests_path
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
        TestCase.from_json_file(test_path, @logger)
      end

      # Load test cases referenced by a suite
      def load_suite_tests(suite)
        suite.tests.map { |test_name| load_test(test_name) }
      end
    end
  end
end
