# frozen_string_literal: true

module AutoHCK
  module Functest
    # Executes individual JSON test steps against a single client VM.
    #
    # Supported step types: guest_run, guest_run_file, files_action,
    # guest_reboot, host_run, barrier, qmp_command, qmp_wait_event.
    class StepHandler
      include Helper

      STEP_HANDLERS = {
        'guest_run_file' => :handle_guest_run_file,
        'guest_run' => :handle_guest_run,
        'files_action' => :handle_files_action,
        'guest_reboot' => :handle_guest_reboot,
        'host_run' => :handle_host_run,
        'barrier' => :handle_barrier,
        'qmp_command' => :handle_qmp_command,
        'qmp_wait_event' => :handle_qmp_wait_event
      }.freeze

      def initialize(project, tools, machine_name, context, default_timeout:)
        @project = project
        @tools = tools
        @machine_name = machine_name
        @context = context
        @logger = project.logger
        @default_timeout = default_timeout
        @file_action_handler = FileActionHandler.new(@tools, @logger)
      end

      def execute_step(step, step_index)
        desc = @context.substitute_variables(step.desc || "Step #{step_index + 1}")
        @logger.info("Executing: #{desc}")

        timeout = step.timeout || @default_timeout

        Timeout.timeout(timeout) do
          execute_step_action(step, desc)
        end
      rescue Timeout::Error
        handle_step_error(step, "Timeout after #{timeout}s: #{desc}")
      rescue StandardError => e
        @logger.error("Step failed: #{desc} - #{e.message}")
        handle_step_error(step, e.message)
      end

      private

      def execute_step_action(step, desc)
        types = STEP_HANDLERS.keys.select { |k| step.public_send(k.to_sym) }
        raise EngineError, "No step type set in: #{desc}" if types.empty?
        raise EngineError, "Multiple step types set (#{types.join(', ')}) in: #{desc}" if types.length > 1

        send(STEP_HANDLERS.fetch(types.first), step, desc)
      end

      def handle_guest_run_file(step, desc)
        run_guest_command(step, read_script_file(step.guest_run_file), desc)
      end

      def handle_guest_run(step, desc = nil)
        run_guest_command(step, step.guest_run, desc)
      end

      def run_guest_command(step, command, desc = nil)
        desc ||= command[0..60]
        command = @context.substitute_variables(command, step.variables)

        output = @tools.run_on_machine(@machine_name, desc, command).to_s
        @logger.debug("Guest output:\n#{output}") unless output.strip.empty?

        if step.capture_output
          @context.set_variable(step.capture_output, output.strip)
          @logger.debug("Captured '#{step.capture_output}': #{output[0..100]}")
        end

        validate_output(output, step)

        { stdout: output }
      end

      def handle_files_action(step, _desc = nil)
        step.files_action.each { |file_op| run_file_op(file_op) }
      end

      def run_file_op(file_op)
        raise EngineError, 'files_action is missing local_path'  if file_op.local_path.nil?
        raise EngineError, 'files_action is missing remote_path' if file_op.remote_path.nil?

        substituted = Models::FileActionConfig.new(
          local_path: @context.substitute_variables(file_op.local_path),
          remote_path: @context.substitute_variables(file_op.remote_path),
          direction: file_op.direction,
          move: file_op.move,
          allow_missing: file_op.allow_missing
        )
        @file_action_handler.handle(@machine_name, substituted)
      end

      def handle_guest_reboot(_step, _desc = nil)
        @tools.restart_machine_and_wait(@machine_name)
      end

      def handle_host_run(step, _desc = nil)
        command = @context.substitute_variables(step.host_run, step.variables)
        @logger.debug("Host command: #{command}")
        run_cmd(command)
      end

      def handle_barrier(step, _desc = nil)
        @logger.info("Barrier: #{step.barrier} (single-VM mode, no-op)")
      end

      # Send a QMP command to the client VM at the hypervisor level.
      # The step JSON mirrors the QMP wire format — use "execute" and "arguments"
      # exactly as you would in a raw QMP session.
      # Example: { "qmp_command": { "execute": "balloon", "arguments": { "value": 536870912 } } }
      def handle_qmp_command(step, _desc = nil)
        qmp    = step.qmp_command
        result = run_qmp_command(qmp.execute, qmp.arguments)
        @context.set_variable(step.capture_output, result.to_json) if step.capture_output
        { result: result }
      end

      def run_qmp_command(cmd, arguments)
        @logger.debug("QMP command: #{cmd} on #{@machine_name} (args: #{arguments.inspect})")
        result = @project.setup_manager.run_hypervisor_client_command(@machine_name, cmd, arguments)
        @logger.debug("QMP result: #{result.inspect}")
        result
      rescue QMPError => e
        raise "QMP command '#{cmd}' failed on #{@machine_name}: #{e.message}"
      end

      # Block until a specific QMP event arrives from the client VM.
      # Step JSON example:
      #   { "qmp_wait_event": { "event": "BALLOON_CHANGE", "timeout": 30 } }
      def handle_qmp_wait_event(step, _desc = nil)
        qmp     = step.qmp_wait_event
        timeout = qmp.timeout || @default_timeout

        @logger.info("Waiting for QMP event '#{qmp.event}' on #{@machine_name} (timeout: #{timeout}s)")
        response = @project.setup_manager.wait_for_hypervisor_client_event(@machine_name, qmp.event, timeout: timeout)
        @logger.debug("QMP event received: #{response.inspect}")

        @context.set_variable(step.capture_output, response.to_json) if step.capture_output
        { event: response }
      rescue QMPError => e
        raise "QMP event '#{qmp.event}' wait failed on #{@machine_name}: #{e.message}"
      end

      def validate_output(output, step)
        if step.expected_output_contains && !output.include?(step.expected_output_contains)
          raise EngineError, "Output validation failed: expected to contain '#{step.expected_output_contains}'"
        end

        return unless step.expected_output_matches

        pattern = Regexp.new(step.expected_output_matches)
        raise EngineError, "Output validation failed: expected to match '#{pattern}'" unless output.match?(pattern)
      end

      def handle_step_error(step, error_message)
        raise error_message unless step.ignore_errors
      end

      # Reads the script file content to be sent inline over WinRM.
      def read_script_file(path)
        full_path = File.expand_path(path)
        raise EngineError, "Script file not found: #{full_path}" unless File.exist?(full_path)

        @logger.debug("Loading script from: #{full_path}")
        File.read(full_path)
      end
    end
  end
end
