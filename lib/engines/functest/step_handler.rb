# frozen_string_literal: true

module AutoHCK
  module Functest
    # Executes functest JSON steps: timeout, error policy, and output validation
    # wrap CommandExecutionManager#execute.
    class StepHandler
      STEP_TYPE_FIELDS = CommandExecutionManager::STEP_TYPE_FIELDS

      # Set after a `parallel` step; nil for every other step type.
      attr_reader :last_branch_results

      def initialize(project, command_execution_manager, context, default_timeout:)
        @project = project
        @command_execution_manager = command_execution_manager
        @context = context
        @logger = project.logger
        @default_timeout = default_timeout
      end

      # rubocop:disable Metrics/AbcSize
      def execute_step(step)
        @last_branch_results = nil
        desc = @context.substitute_variables(step.desc)
        @logger.info("Executing: #{desc}")

        timeout = step.timeout || @default_timeout

        return execute_set_variable(step) if step.set_variable

        return execute_parallel(step, desc, timeout) if step.parallel

        # Skip timeout for files_action steps
        return execute_and_handle(step, desc) if step.files_action.any?

        Timeout.timeout(timeout) { execute_and_handle(step, desc) }
      rescue Timeout::Error
        handle_step_error(step, "Timeout after #{timeout}s: #{desc}")
      rescue StandardError => e
        @logger.error("Step failed: #{desc} - #{e.message}")
        handle_step_error(step, e.message)
      end
      # rubocop:enable Metrics/AbcSize

      private

      def execute_parallel(step, desc, timeout)
        validate_step_type!(step, desc)

        runner = ParallelBranchRunner.new(@project, @command_execution_manager, @context, @logger, @default_timeout)
        Timeout.timeout(timeout) { runner.run(step) }
      ensure
        @last_branch_results = runner&.branch_results
      end

      def validate_step_type!(step, desc)
        types = STEP_TYPE_FIELDS.select { |field| step.step_type_active?(field) }
        raise EngineError, "No step type set in: #{desc}" if types.empty?
        raise EngineError, "Multiple step types set (#{types.join(', ')}) in: #{desc}" if types.length > 1
      end

      def execute_set_variable(step)
        step.set_variable.each do |name, value|
          resolved = @context.substitute_variables(value)
          @logger.debug("Overwriting variable '#{name}'") if @context.replacement_map["@#{name}@"]
          @context.set_variable(name, resolved)
        end
      end

      def execute_and_handle(step, desc)
        validate_step_type!(step, desc)
        result = @command_execution_manager.execute(step, replacement: step_replacement(step))
        handle_step_result(result, step)
      end

      def step_replacement(step)
        return @context.replacement_map if step.variables.empty?

        extra = step.variables.each_with_object({}) do |(placeholder, var_name), hash|
          value = @context.substitute_variables("@#{var_name}@")
          hash[placeholder] = value unless value.empty?
        end

        @context.replacement_map.merge(extra)
      end

      def handle_step_result(result, step)
        primary_output = guest_output(result, step)
        @logger.debug("Guest output:\n#{primary_output}") unless primary_output.strip.empty?

        if step.capture_output
          captured = capture_value(result, primary_output, step)
          @context.set_variable(step.capture_output, captured)
          @logger.debug("Captured '#{step.capture_output}': #{captured.to_s[0..100]}")
        end

        validate_outputs(result, step)
      end

      def guest_outputs(result)
        result.fetch(:guest_outputs, {})
      end

      # Only used by capture_output, since it can only store one value.
      # expected_output_contains/matches don't use this — they use
      # #validate_outputs instead, to check every target machine.
      def guest_output(result, step)
        machine = @command_execution_manager.primary_machine(step)
        guest_outputs(result).fetch(machine, '').to_s
      end

      # qmp_result/qmp_event are keyed by machine name, so pick out the
      # primary machine's value instead of capturing every machine's.
      def capture_value(result, guest_output, step)
        return guest_output.strip unless guest_output.strip.empty?

        machine = @command_execution_manager.primary_machine(step)
        return result[:qmp_result][machine].to_json if result[:qmp_result]
        return result[:qmp_event][machine].to_json if result[:qmp_event]

        ''
      end

      # Checks expected_output_contains/matches on every machine the step
      # ran on. If any one of them fails, the step fails.
      def validate_outputs(result, step)
        outputs = guest_outputs(result)
        if outputs.empty?
          host_output = result[:host_output]
          return validate_output(host_output.to_s, step, 'host') if host_output

          return validate_output('', step)
        end

        outputs.each { |machine, output| validate_output(output.to_s, step, machine) }
      end

      def validate_output_matches(output, step, target)
        encoding = nil
        if step.expected_output_matches_encoding == 'Regexp::NOENCODING'
          encoding = Regexp::NOENCODING
          output = output.dup.force_encoding('BINARY')
        end

        pattern = Regexp.new(step.expected_output_matches, encoding)
        @logger.debug("Compiled expected_output_matches pattern: #{pattern}")
        return if output.match?(pattern)

        raise EngineError, "Output validation failed#{target}: expected to match '#{pattern}'"
      end

      def validate_output(output, step, machine = nil)
        target = machine ? " on #{machine}" : ''
        if step.expected_output_contains && !output.include?(step.expected_output_contains)
          raise EngineError, "Output validation failed#{target}: expected to contain '#{step.expected_output_contains}'"
        end

        return unless step.expected_output_matches

        validate_output_matches(output, step, target)
      end

      def handle_step_error(step, error_message)
        raise error_message unless step.ignore_errors
      end
    end
  end
end
