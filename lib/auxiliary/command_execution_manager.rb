# typed: true
# frozen_string_literal: true

module AutoHCK
  # Executes Models::CommandInfo guest, host, file, reboot, QMP, and barrier
  # actions against one or more machines via Tools / FunctestTools.
  class CommandExecutionManager
    extend T::Sig
    include Helper

    SLEEP_AFTER_REBOOT = 60
    DEFAULT_FILE_ACTION_REMOTE_PATH = 'C:\\'
    DEFAULT_FILE_ACTION_LOCAL_PATH = '@workspace@'
    DEFAULT_TIMEOUT = 300

    RebootStrategy = T.let({
      FixedSleep: :fixed_sleep,
      WinrmPoll: :winrm_poll
    }.freeze, T::Hash[Symbol, Symbol])

    INIT_OPTS_DEFAULTS = T.let({
      reboot_strategy: RebootStrategy[:FixedSleep],
      reboot_callback: nil,
      default_timeout: DEFAULT_TIMEOUT
    }.freeze, T::Hash[Symbol, T.untyped])

    STEP_TYPE_FIELDS = T.let(%i[
      guest_run guest_run_file guest_reboot files_action host_run host_run_file
      barrier qmp_command qmp_wait_event
    ].freeze, T::Array[Symbol])

    sig { params(init_opts: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def validate_init_opts(init_opts)
      extra_keys = init_opts.keys - INIT_OPTS_DEFAULTS.keys
      unless extra_keys.empty?
        raise AutoHCKError.new('initialize'),
              "Undefined initialization options: #{extra_keys.join(', ')}."
      end

      INIT_OPTS_DEFAULTS.merge(init_opts)
    end

    sig do
      params(
        project: Project,
        tools: Tools,
        machines: T::Array[String],
        init_opts: T::Hash[Symbol, T.untyped]
      ).void
    end
    def initialize(project:, tools:, machines:, init_opts: {})
      init_opts = validate_init_opts(init_opts)

      @project = project
      @tools = tools
      @logger = project.logger
      @machines = machines
      @file_action_handler = FileActionHandler.new(@tools, @logger)

      @reboot_strategy = init_opts[:reboot_strategy]
      @reboot_callback = init_opts[:reboot_callback]
      @default_timeout = init_opts[:default_timeout]
    end

    sig do
      params(
        command_info: Models::CommandInfo,
        replacement: ReplacementMap
      ).returns(T::Hash[Symbol, T.untyped])
    end
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    def execute(command_info, replacement: ReplacementMap.new)
      desc = command_desc(command_info)
      result = T.let({ desc: desc }, T::Hash[Symbol, T.untyped])

      result[:guest_outputs] = execute_guest(command_info, replacement, desc) if guest_command?(command_info)
      execute_guest_reboot(desc) if command_info.guest_reboot
      execute_host(command_info, replacement, desc) if host_command?(command_info)
      execute_files_actions(command_info, replacement) unless command_info.files_action.empty?
      execute_barrier(command_info) if command_info.barrier
      result[:qmp_result] = execute_qmp_command(command_info, replacement) if command_info.qmp_command
      result[:qmp_event] = execute_qmp_wait_event(command_info) if command_info.qmp_wait_event

      result
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

    sig { params(machine_name: String).returns(ReplacementMap) }
    def machine_replacement_map(machine_name)
      @project.project_replacement_map.merge(@project.setup_manager.client_replacement_map(machine_name))
    end

    private

    sig { params(command_info: Models::CommandInfo).returns(String) }
    def command_desc(command_info)
      command_info.desc
    end

    sig { params(command_info: Models::CommandInfo).returns(T::Boolean) }
    def guest_command?(command_info)
      !!(command_info.guest_run || command_info.guest_run_file)
    end

    sig { params(command_info: Models::CommandInfo).returns(T::Boolean) }
    def host_command?(command_info)
      !!(command_info.host_run || command_info.host_run_file)
    end

    sig do
      params(
        command_info: Models::CommandInfo,
        replacement: ReplacementMap,
        desc: String
      ).returns(T::Hash[String, T.untyped])
    end
    def execute_guest(command_info, replacement, desc)
      outputs = {}

      @machines.each do |machine_name|
        @logger.info("Running command (#{desc}) on client #{machine_name}")
        command = resolve_guest_command(command_info, machine_name, replacement)
        @logger.debug("Running command after replacement (#{desc}) on client #{machine_name}: #{command}")

        outputs[machine_name] = @tools.run_on_machine(machine_name, desc, command)
      end

      outputs
    end

    sig { params(desc: String).void }
    def execute_guest_reboot(desc)
      @machines.each do |machine_name|
        reboot_machine(machine_name, desc)
      end
    end

    sig do
      params(
        command_info: Models::CommandInfo,
        replacement: ReplacementMap,
        desc: String
      ).void
    end
    def execute_host(command_info, replacement, desc)
      command = resolve_host_command(command_info, replacement)
      @logger.info("Running command (#{desc}) on host")
      @logger.debug("Host command: #{command}")
      run_cmd(command)
    end

    sig { params(command_info: Models::CommandInfo, replacement: ReplacementMap).void }
    def execute_files_actions(command_info, replacement)
      command_info.files_action.each do |files_action|
        if files_action.remote_path.nil? && files_action.local_path.nil?
          @logger.warn('Both remote and local paths are nil, skipping file action')
          next
        end

        @machines.each do |machine_name|
          action = prepare_file_action(files_action, machine_name, replacement, command_info)
          @file_action_handler.handle(machine_name, action)
        end
      end
    end

    sig do
      params(
        files_action: Models::FileActionConfig,
        machine_name: String,
        replacement: ReplacementMap,
        command_info: Models::CommandInfo
      ).returns(Models::FileActionConfig)
    end
    def prepare_file_action(files_action, machine_name, replacement, command_info)
      map = replacement_map_for(machine_name, replacement, command_info)
            .merge({ '@client_name@' => machine_name })
      files_action.dup_and_replace_path(map, DEFAULT_FILE_ACTION_REMOTE_PATH,
                                        DEFAULT_FILE_ACTION_LOCAL_PATH)
    end

    sig { params(command_info: Models::CommandInfo).void }
    def execute_barrier(command_info)
      @logger.info("Barrier: #{command_info.barrier} (single-VM mode, no-op)")
    end

    def run_qmp_command(execute, arguments, machine_name)
      @logger.debug("QMP command: #{execute} on #{machine_name} (args: #{arguments.inspect})")
      result = @project.setup_manager.run_hypervisor_client_command(machine_name, execute, arguments)
      @logger.debug("QMP result: #{result.inspect}")
      result
    end

    sig { params(command_info: Models::CommandInfo, replacement: ReplacementMap).returns(T.untyped) }
    def execute_qmp_command(command_info, replacement)
      qmp = T.must(command_info.qmp_command)
      execute = qmp.execute

      outputs = {}
      @machines.each do |machine_name|
        map = replacement_map_for(machine_name, replacement, command_info)
        arguments = qmp.arguments && map.replace(qmp.arguments)
        outputs[machine_name] = run_qmp_command(execute, arguments, machine_name)
      rescue QMPError => e
        raise EngineError, "QMP command '#{execute}' failed on #{machine_name}: #{e.message}"
      end

      outputs
    end

    sig { params(event: String, machine_name: String, timeout: Integer).returns(T.untyped) }
    def run_qmp_wait_event(event, machine_name, timeout)
      @logger.info("Waiting for QMP event '#{event}' on #{machine_name} (timeout: #{timeout}s)")
      response = @project.setup_manager.wait_for_hypervisor_client_event(machine_name, event, timeout: timeout)
      @logger.debug("QMP event received: #{response.inspect}")

      response
    end

    sig { params(command_info: Models::CommandInfo).returns(T.untyped) }
    def execute_qmp_wait_event(command_info)
      qmp = T.must(command_info.qmp_wait_event)
      timeout = qmp.timeout || command_info.timeout || @default_timeout
      event = qmp.event

      outputs = {}
      @machines.each do |machine_name|
        outputs[machine_name] = run_qmp_wait_event(event, machine_name, timeout)
      rescue QMPError => e
        raise EngineError, "QMP event '#{event}' wait failed on #{machine_name}: #{e.message}"
      end

      outputs
    end

    sig do
      params(
        command_info: Models::CommandInfo,
        machine_name: String,
        replacement: ReplacementMap
      ).returns(String)
    end
    def resolve_guest_command(command_info, machine_name, replacement)
      command = if command_info.guest_run_file
                  read_script_file(T.must(command_info.guest_run_file))
                else
                  T.must(command_info.guest_run)
                end

      replacement_map_for(machine_name, replacement, command_info).replace(command)
    end

    sig { params(command_info: Models::CommandInfo, replacement: ReplacementMap).returns(String) }
    def resolve_host_command(command_info, replacement)
      command = if command_info.host_run_file
                  read_script_file(T.must(command_info.host_run_file))
                else
                  T.must(command_info.host_run)
                end

      apply_variables(replacement, command_info.variables).create_cmd(command)
    end

    sig do
      params(
        machine_name: String,
        replacement: ReplacementMap,
        command_info: Models::CommandInfo
      ).returns(ReplacementMap)
    end
    def replacement_map_for(machine_name, replacement, command_info)
      apply_variables(
        machine_replacement_map(machine_name).merge(replacement),
        command_info.variables
      )
    end

    sig do
      params(
        map: ReplacementMap,
        variables: T::Hash[String, String]
      ).returns(ReplacementMap)
    end
    def apply_variables(map, variables)
      return map if variables.empty?

      extra = variables.each_with_object({}) do |(placeholder, var_name), hash|
        value = map["@#{var_name}@"]
        @logger.warn("Variable '#{var_name}' not found for placeholder '#{placeholder}'") if value.nil?
        hash[placeholder] = value unless value.nil?
      end

      map.merge(extra)
    end

    sig { params(path: String).returns(String) }
    def read_script_file(path)
      full_path = File.expand_path(path)
      raise EngineError, "Script file not found: #{full_path}" unless File.exist?(full_path)

      @logger.debug("Loading script from: #{full_path}")
      File.read(full_path)
    end

    sig { params(machine_name: String, desc: String).void }
    def reboot_machine(machine_name, desc)
      if @reboot_callback
        @logger.info("Rebooting client #{machine_name} after command (#{desc})")
        @reboot_callback.call(machine_name)
        return
      end

      case @reboot_strategy
      when RebootStrategy[:WinrmPoll]
        @logger.info("Rebooting client #{machine_name} after command (#{desc})")
        @tools.restart_machine_and_wait(machine_name)
      else
        @logger.info("Rebooting client #{machine_name} after command (#{desc}) " \
                     "and sleeping for #{SLEEP_AFTER_REBOOT} seconds")
        @tools.restart_machine(machine_name)
        sleep SLEEP_AFTER_REBOOT
      end
    end
  end
end
