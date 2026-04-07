# typed: false
# frozen_string_literal: true

module AutoHCK
  # Bridges WinRM (Session 0) to the interactive desktop (Session 1).
  #
  # WinRM runs in a non-interactive service session and cannot touch
  # the UI. This class deploys a PowerShell agent into the user's
  # desktop session via a scheduled task with LogonType Interactive,
  # then communicates through a filesystem queue:
  #
  #   1. Host writes a command to  C:\UIAgent\queue\<id>.ps1
  #   2. Agent executes it and writes C:\UIAgent\queue\<id>.json
  #   3. Host polls for the .json result and cleans up
  #
  # A Registry Run key re-launches the agent after VM reboots
  # that some HLK tests trigger.
  class UIExecutor
    AGENT_DIR = 'C:\\UIAgent'
    QUEUE_DIR = "#{AGENT_DIR}\\queue".freeze
    AGENT_PATH = "#{AGENT_DIR}\\agent.ps1".freeze
    READY_PATH = "#{AGENT_DIR}\\agent.ready".freeze
    LOG_PATH = "#{AGENT_DIR}\\agent.log".freeze
    WATCHERS_DIR = "#{AGENT_DIR}\\watchers".freeze
    TASK_NAME = 'AutoHCK_UIAgent'
    AUTOSTART_KEY = 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run'
    AUTOSTART_NAME = 'AutoHCK_UIAgent'
    LOCAL_AGENT = File.join(__dir__, 'agent.ps1')
    LOCAL_WATCHERS = File.join(__dir__, 'watchers')

    DEFAULT_TIMEOUT = 120
    POLL_INTERVAL = 2
    DEPLOY_VERIFY_RETRIES = 10
    DEPLOY_VERIFY_INTERVAL = 3

    class DeployError < AutoHCKError; end
    class CommandTimeoutError < AutoHCKError; end
    class CommandError < AutoHCKError; end

    def initialize(tools, machine, logger)
      @tools = tools
      @machine = machine
      @logger = logger
      @deployed = false
    end

    # Deploys the agent if not already running
    def deploy
      if agent_alive?
        @logger.info("UI agent already running on #{@machine}, skipping deploy")
        @deployed = true
        return
      end

      @logger.info("Deploying UI agent on #{@machine}")
      create_directories
      upload_agent
      upload_watchers
      register_startup_task
      register_agent_autostart
      remove_stale_ready_marker
      start_agent
      verify_agent_running
      @deployed = true
      @logger.info("UI agent deployed and running on #{@machine}")
    rescue StandardError => e
      raise DeployError, "Failed to deploy UI agent on #{@machine}: #{e.message}"
    end

    # Executes a PowerShell command in the interactive session.
    # Deploys the agent on first call if not already running.
    def run(command, timeout: DEFAULT_TIMEOUT)
      deploy unless @deployed

      id = "cmd_#{SecureRandom.hex(8)}"
      script_path = "#{QUEUE_DIR}\\#{id}.ps1"
      result_path = "#{QUEUE_DIR}\\#{id}.json"

      submit_command(id, command, script_path)
      result = wait_for_result(id, result_path, timeout)
      cleanup_result(result_path)
      log_result(id, result)
      result
    end

    def teardown
      @logger.info("Tearing down UI agent on #{@machine}")
      remove_agent_autostart
      @tools.run_on_machine(
        @machine,
        'Stop UI agent task',
        "schtasks /Delete /TN #{TASK_NAME} /F"
      )
      @deployed = false
    rescue StandardError => e
      @logger.warn("Failed to tear down UI agent on #{@machine}: #{e.message}")
    end

    def agent_log
      @tools.run_on_machine(
        @machine,
        'Read UI agent log',
        "Get-Content '#{LOG_PATH}' -ErrorAction SilentlyContinue"
      )
    end

    private

    def create_directories
      @tools.run_on_machine(
        @machine,
        'Create UI agent directories',
        "New-Item -ItemType Directory -Path '#{QUEUE_DIR}','#{WATCHERS_DIR}' -Force"
      )
    end

    def upload_agent
      @tools.upload_to_machine(@machine, LOCAL_AGENT, AGENT_PATH)
    end

    # Uploads watcher scripts (.au3) that driver configs can launch
    # via pre/post_test_commands.
    def upload_watchers
      return unless File.directory?(LOCAL_WATCHERS)

      Dir.glob(File.join(LOCAL_WATCHERS, '*.au3')).each do |file|
        remote = "#{WATCHERS_DIR}\\#{File.basename(file)}"
        @logger.info("Uploading watcher #{File.basename(file)} to #{@machine}")
        @tools.upload_to_machine(@machine, file, remote)
      end
    end

    # HLK may switch the active session user (e.g. DTMLLUAdminUser),
    # so we detect the current one for the scheduled task principal.
    def interactive_user
      user = @tools.run_on_machine(
        @machine,
        'Detect interactive session user',
        '(Get-WmiObject -Class Win32_ComputerSystem).UserName'
      ).to_s.strip
      @logger.debug("Interactive session user on #{@machine}: '#{user}'")
      user.empty? ? 'Administrator' : user.split('\\').last
    end

    # Interactive logon type places the process in Session 1 (desktop).
    def register_startup_task
      user = interactive_user
      ps_cmd = <<~PS.gsub("\n", ' ').strip
        $action = New-ScheduledTaskAction
          -Execute 'powershell.exe'
          -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File #{AGENT_PATH}';
        $principal = New-ScheduledTaskPrincipal
          -UserId '#{user}'
          -LogonType Interactive
          -RunLevel Highest;
        Register-ScheduledTask
          -TaskName '#{TASK_NAME}'
          -Action $action
          -Principal $principal
          -Force
      PS
      @tools.run_on_machine(@machine, 'Register UI agent scheduled task', ps_cmd)
    end

    # schtasks /Run is one-shot; the Run key survives VM reboots.
    def register_agent_autostart
      agent_cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File #{AGENT_PATH}"
      @tools.run_on_machine(
        @machine,
        'Register UI agent autostart on logon',
        "Set-ItemProperty -Path '#{AUTOSTART_KEY}' -Name '#{AUTOSTART_NAME}' -Value '#{agent_cmd}' -Force"
      )
    end

    def remove_agent_autostart
      @tools.run_on_machine(
        @machine,
        'Remove UI agent autostart',
        "Remove-ItemProperty -Path '#{AUTOSTART_KEY}' -Name '#{AUTOSTART_NAME}' -Force -ErrorAction SilentlyContinue"
      )
    end

    def start_agent
      @tools.run_on_machine(
        @machine,
        'Start UI agent task',
        "schtasks /Run /TN #{TASK_NAME}"
      )
    end

    # Checks ready marker, then process command line, then task status
    # to cover both initial launch and post-reboot restart via Run key.
    def agent_alive?
      return false unless @tools.exists_on_machine?(@machine, READY_PATH)

      check = @tools.run_on_machine(
        @machine,
        'Check UI agent process',
        "Get-WmiObject Win32_Process -Filter \"Name='powershell.exe'\" | " \
        "Where-Object { $_.CommandLine -like '*agent.ps1*' } | " \
        "Select-Object -First 1 | ForEach-Object { 'agent_running' }"
      )
      return true if check.to_s.include?('agent_running')

      status = @tools.run_on_machine(
        @machine,
        'Check UI agent task status',
        "schtasks /Query /TN #{TASK_NAME} /FO CSV /NH"
      )
      status.to_s.include?('Running')
    rescue StandardError
      false
    end

    def remove_stale_ready_marker
      @tools.run_on_machine(
        @machine,
        'Remove stale agent ready marker',
        "if (Test-Path '#{READY_PATH}') { Remove-Item -Path '#{READY_PATH}' -Force }"
      )
    end

    # Polls for the ready marker that agent.ps1 creates after init.
    def verify_agent_running
      DEPLOY_VERIFY_RETRIES.times do
        if @tools.exists_on_machine?(@machine, READY_PATH)
          @logger.info("UI agent ready marker found on #{@machine}")
          return
        end

        @logger.debug("Waiting for UI agent ready marker on #{@machine}...")
        sleep DEPLOY_VERIFY_INTERVAL
      end
      raise DeployError, "UI agent did not become ready on #{@machine} after verification"
    end

    # Drops a .ps1 into the queue; the agent picks it up automatically.
    def submit_command(id, command, script_path)
      @logger.info("Submitting UI command #{id} on #{@machine}")
      escaped = command.gsub("'", "''")
      @tools.run_on_machine(
        @machine,
        "Submit UI command #{id}",
        "[System.IO.File]::WriteAllText('#{script_path}', '#{escaped}')"
      )
    end

    # Polls until the agent writes the .json result or timeout expires.
    def wait_for_result(id, result_path, timeout)
      deadline = Time.now + timeout
      loop do
        if Time.now > deadline
          raise CommandTimeoutError,
                "UI command #{id} on #{@machine} timed out after #{timeout}s"
        end

        if @tools.exists_on_machine?(@machine, result_path)
          raw = @tools.run_on_machine(
            @machine,
            "Read UI result #{id}",
            "Get-Content '#{result_path}' -Raw"
          )
          return JSON.parse(raw)
        end

        sleep POLL_INTERVAL
      end
    end

    def cleanup_result(result_path)
      @tools.delete_on_machine(@machine, result_path)
    rescue StandardError => e
      @logger.warn("Failed to clean up result file #{result_path}: #{e.message}")
    end

    def log_result(id, result)
      exit_code = result['exit_code']
      if exit_code.zero?
        @logger.info("UI command #{id} succeeded on #{@machine} (exit_code=0)")
      else
        @logger.warn("UI command #{id} failed on #{@machine} (exit_code=#{exit_code})")
      end

      @logger.info("UI command #{id} stdout: #{result['stdout']}") unless result['stdout'].to_s.empty?
      @logger.warn("UI command #{id} stderr: #{result['stderr']}") unless result['stderr'].to_s.empty?
    end
  end
end
