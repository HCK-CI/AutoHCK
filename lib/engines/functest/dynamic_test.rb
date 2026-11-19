# frozen_string_literal: true

module AutoHCK
  module Functest
    # Namespace for dynamic test class factories. Each dynamic test's .rb file
    # defines a method here named after the JSON basename (e.g. vm_pause_resume)
    # that returns the DynamicTest subclass to instantiate.
    module DynamicTests
    end

    # Base class for Ruby-driven functest cases. JSON still supplies metadata
    # (name, clients, snapshots, timeout, …); when `"dynamic": true`, AutoHCK
    # loads the sibling .rb and delegates pre/steps/cleanup here.
    #
    # Subclasses receive the same runtime handles TestExecutor uses:
    # @project, @clients, @tools, @context, @command_execution_manager,
    # @step_handler, and @logger.
    class DynamicTest
      def initialize(executor)
        @project = executor.project
        @clients = executor.clients
        @tools = executor.tools
        @context = executor.context
        @command_execution_manager = executor.command_execution_manager
        @step_handler = executor.step_handler
        @logger = @project.logger
        @executor = executor
      end

      def run_pre_test_commands(_test); end

      def execute_test_steps(_test, _result)
        raise NotImplementedError, "#{self.class} must implement #execute_test_steps"
      end

      def run_cleanup(_test); end

      protected

      # Runs a CommandInfo step through StepHandler and appends a step result
      # entry, matching JSON-driven step reporting.
      def execute_and_record(step, result)
        index = result[:steps].length
        result[:steps] << @executor.execute_test_step(step, index)
      end

      # Runs via CommandExecutionManager (no StepHandler output checks) and
      # records a step result. Returns the raw execute() hash.
      def execute_raw_and_record(step, result)
        index = result[:steps].length
        desc = @context.substitute_variables(step.desc)
        start_time = Time.now
        step_result = {
          index: index, description: desc, status: 'running',
          start_time: start_time.utc.iso8601
        }
        outputs = @command_execution_manager.execute(step, replacement: @context.replacement_map)
        finalize_recorded_step(step_result, result, start_time, 'passed')
        outputs
      rescue StandardError => e
        finalize_recorded_step(step_result, result, start_time, 'failed', e.message)
        raise
      end

      def qmp_command(execute, arguments: nil, desc: nil, timeout: 30)
        Models::CommandInfo.new(
          desc: desc || "QMP: #{execute}",
          qmp_command: Models::QmpCommandConfig.new(execute: execute, arguments: arguments),
          timeout: timeout
        )
      end

      def guest_run(command, desc:, expected_output_contains: nil, timeout: 60)
        Models::CommandInfo.new(
          desc: desc,
          guest_run: command,
          expected_output_contains: expected_output_contains,
          timeout: timeout
        )
      end

      def primary_qmp_result(outputs, step)
        machine = @command_execution_manager.primary_machine(step)
        outputs.fetch(:qmp_result).fetch(machine)
      end

      private

      def finalize_recorded_step(step_result, result, start_time, status, error = nil)
        end_time = Time.now
        step_result[:status] = status
        step_result[:error] = error if error
        step_result[:end_time] = end_time.utc.iso8601
        step_result[:duration] = end_time - start_time
        log_recorded_step(step_result, status, error)
        result[:steps] << step_result
      end

      def log_recorded_step(step_result, status, error)
        if status == 'passed'
          @logger.info("  PASS: #{step_result[:description]}")
        else
          @logger.error("  FAIL: #{step_result[:description]} - #{error}")
        end
      end
    end
  end
end
