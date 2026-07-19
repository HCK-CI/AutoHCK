# frozen_string_literal: true

module AutoHCK
  module Functest
    # Drives test execution: runs each test's steps in order, records pass/fail
    # per step and per test, runs cleanup regardless of outcome, and produces
    # a summary hash written to functest_results.json.
    class TestExecutor
      attr_reader :results, :context

      def test_results
        @test_results ||= @results.map { |r| Models::TestResult.from_functest(r) }
      end

      # clients is every FunctestClient booted for this run. tools and
      # command_execution_manager are shared by all of them.
      def initialize(project, clients, tools, command_execution_manager, default_timeout:)
        @project = project
        @clients = clients
        @tools = tools
        @machine_names = clients.map(&:name)
        @logger = project.logger
        @context = TestContext.new(project, clients.first.replacement_map)
        @command_execution_manager = command_execution_manager
        @step_handler = StepHandler.new(project, @command_execution_manager, @context,
                                        default_timeout: default_timeout)
        @results = []
      end

      def execute_test(test)
        log_section("Starting test: #{test.name}")
        @logger.info("Description: #{@context.substitute_variables(test.description)}") if test.description
        record_test(test)
      end

      def execute_tests(tests)
        @logger.info("Executing #{tests.length} test(s)")
        tests.each { |test| execute_test(test) }
        summary
      end

      def summary
        total = @results.length
        passed = @results.count { |r| r[:status] == 'passed' }
        failed = @results.count { |r| r[:status] == 'failed' }

        @logger.info('')
        log_section('TEST SUMMARY')
        @logger.info("Total:  #{total}")
        @logger.info("Passed: #{passed}")
        @logger.info("Failed: #{failed}")
        @logger.info('-' * 80)

        { total: total, passed: passed, failed: failed, results: @results }
      end

      private

      def record_test(test)
        start_time = Time.now
        result = { name: test.name, description: test.description,
                   status: 'running', steps: [], start_time: start_time.utc.iso8601 }
        run_test_steps(test, result)
        result
      ensure
        finalize_result(result, test, start_time)
      end

      def finalize_result(result, test, start_time)
        run_cleanup(test)
        result[:dump_path] = collect_memory_dumps(test.name)
        end_time = Time.now
        result[:end_time] = end_time.utc.iso8601
        result[:duration] = end_time - start_time
        @results << result
      end

      def run_test_steps(test, result)
        prepare_test_clients!(test)
        test.test_steps.each_with_index { |step, index| result[:steps] << execute_test_step(step, index) }
        result[:status] = 'passed'
        @logger.info("PASSED: #{test.name}")
      rescue StandardError => e
        result[:status] = 'failed'
        result[:error] = e.message
        @logger.error("FAILED: #{test.name} - #{e.message}")
      end

      # Sets CommandExecutionManager's default machines to this test's own
      # clients. Then fails the test right away if any step (including
      # cleanup) targets a client this test didn't declare.
      def prepare_test_clients!(test)
        @command_execution_manager.scope_to_test(test.clients)

        (test.test_steps + test.cleanup).each do |step|
          unknown = step.clients - test.clients
          next if unknown.empty?

          raise EngineError, "Test '#{test.name}' step targets client(s) #{unknown.join(', ')} not declared " \
                             "in this test case's own clients list (#{test.clients.join(', ')})"
        end
      end

      def execute_test_step(step, index)
        desc = @context.substitute_variables(step.desc || "Step #{index + 1}")
        start_time = Time.now
        step_result = { index: index, description: desc, status: 'running', start_time: start_time.utc.iso8601 }
        run_step(step, index, step_result, desc)
        step_result
      ensure
        end_time = Time.now
        step_result[:end_time] = end_time.utc.iso8601
        step_result[:duration] = end_time - start_time
      end

      def run_step(step, index, step_result, desc)
        @step_handler.execute_step(step, index)
        step_result[:status] = 'passed'
        @logger.info("  PASS: #{desc}")
      rescue StandardError => e
        step_result[:status] = 'failed'
        step_result[:error] = e.message
        @logger.error("  FAIL: #{desc} - #{e.message}")
        raise
      end

      def log_section(title)
        @logger.info('=' * 80)
        @logger.info(title)
        @logger.info('=' * 80)
      end

      def run_cleanup(test)
        return if test.cleanup.empty?

        @logger.info('Running cleanup steps...')
        test.cleanup.each_with_index do |step, index|
          @step_handler.execute_step(step, index)
        rescue StandardError => e
          @logger.warn("Cleanup step failed (ignoring): #{e.message}")
        end
      end

      def collect_memory_dumps(test_name)
        id = test_name.gsub(/\W/, '_')
        MemoryDumpCollector.new(@tools, @machine_names, @project.workspace_path, @logger).collect(id)
      end
    end
  end
end
