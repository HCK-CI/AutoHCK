# frozen_string_literal: true

module AutoHCK
  module Functest
    # Executes functest JSON steps: timeout, error policy, and output validation
    # wrap CommandExecutionManager#execute.
    class StepHandler
      STEP_TYPE_FIELDS = CommandExecutionManager::STEP_TYPE_FIELDS

      def initialize(project, command_execution_manager, context, default_timeout:)
        @project = project
        @command_execution_manager = command_execution_manager
        @context = context
        @logger = project.logger
        @default_timeout = default_timeout
      end

      def execute_step(step, step_index)
        desc = @context.substitute_variables(step.desc || "Step #{step_index + 1}")
        @logger.info("Executing: #{desc}")

        timeout = step.timeout || @default_timeout

        Timeout.timeout(timeout) do
          validate_step_type!(step, desc)
          result = @command_execution_manager.execute(step, replacement: step_replacement(step))
          handle_step_result(result, step)
        end
      rescue Timeout::Error
        handle_step_error(step, "Timeout after #{timeout}s: #{desc}")
      rescue StandardError => e
        @logger.error("Step failed: #{desc} - #{e.message}")
        handle_step_error(step, e.message)
      end

      private

      def validate_step_type!(step, desc)
        types = STEP_TYPE_FIELDS.select { |field| step_type_set?(step, field) }
        raise EngineError, "No step type set in: #{desc}" if types.empty?
        raise EngineError, "Multiple step types set (#{types.join(', ')}) in: #{desc}" if types.length > 1
      end

      def step_type_set?(step, field)
        value = step.public_send(field)
        case field
        when :files_action then value.any?
        when :guest_reboot then value == true
        when :guest_run, :guest_run_file, :host_run, :host_run_file, :barrier
          value.is_a?(String) ? !value.empty? : !value.nil?
        else
          !value.nil?
        end
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
        return validate_output('', step) if outputs.empty?

        outputs.each { |machine, output| validate_output(output.to_s, step, machine) }
      end

      def validate_output(output, step, machine = nil)
        target = machine ? " on #{machine}" : ''
        if step.expected_output_contains && !output.include?(step.expected_output_contains)
          raise EngineError, "Output validation failed#{target}: expected to contain '#{step.expected_output_contains}'"
        end

        return unless step.expected_output_matches

        pattern = Regexp.new(step.expected_output_matches)
        return if output.match?(pattern)

        raise EngineError, "Output validation failed#{target}: expected to match '#{pattern}'"
      end

      def handle_step_error(step, error_message)
        raise error_message unless step.ignore_errors
      end
    end
  end
end
