# frozen_string_literal: true

module AutoHCK
  # Tools wrapper for the functest engine.
  #
  # Subclasses AutoHCK::Tools to inherit its retry logic, thread-safe mutex,
  # error handling, and machine-level methods (run_on_machine,
  # upload_to_machine, download_from_machine, install_machine_driver_package).
  #
  # Connects with no_studio: true — no Studio IP is needed for functest.
  # Adds restart_machine_and_wait — shuts down the VM and polls WinRM
  # until it comes back up, replacing hcktest's Studio-based return_when_client_up.
  class FunctestTools < Tools
    WINRM_SETTLE_SLEEP = 15
    WAIT_WINRM_TIMEOUT = 600
    WAIT_WINRM_INTERVAL = 10

    def initialize(project, clients_addrs)
      super(project, no_studio: true, clients_addrs: clients_addrs)
    end

    # Restart the VM and block until WinRM is reachable again.
    # First waits for WinRM to go down (machine is actually offline), then
    # waits for it to come back up. This prevents a false positive when the
    # guest OS shuts down slowly (e.g. with Driver Verifier enabled) and WinRM
    # is still reachable when we start polling.
    def restart_machine_and_wait(machine)
      restart_machine(machine)
      wait_for_machine_winrm_down(machine)
      wait_for_machine_winrm(machine)
      @logger.info("#{machine} is back after reboot")
    end

    # Block until WinRM is reachable. Driver install steps do this implicitly;
    # functest runs without -d need an explicit wait before guest steps run.
    def wait_for_client_online(machine)
      wait_for_machine_winrm(machine)
      @logger.info("#{machine} is online")
    end

    private

    def wait_for_machine_winrm_down(machine)
      addr = @clients_addrs[machine][:addr]
      port = @clients_addrs[machine][:port] || @config['winrm_port'] || 5985
      @logger.info("Waiting for #{machine} to go offline...")
      deadline = Time.now + WAIT_WINRM_TIMEOUT
      while winrm_port_open?(addr, port)
        raise RestartMachineError, "#{machine} did not go offline within #{WAIT_WINRM_TIMEOUT}s" \
          if Time.now > deadline

        sleep WAIT_WINRM_INTERVAL
      end
      @logger.debug("#{machine} is now offline")
    end

    def wait_for_machine_winrm(machine)
      addr = @clients_addrs[machine][:addr]
      port = @clients_addrs[machine][:port] || @config['winrm_port'] || 5985
      @logger.info("Waiting for WinRM on #{machine} (#{addr}:#{port})...")
      deadline = Time.now + WAIT_WINRM_TIMEOUT
      until winrm_port_open?(addr, port)
        raise RestartMachineError, "WinRM not reachable on #{machine} after #{WAIT_WINRM_TIMEOUT}s" \
          if Time.now > deadline

        sleep WAIT_WINRM_INTERVAL
      end
      sleep WINRM_SETTLE_SLEEP
    end

    def winrm_port_open?(addr, port)
      Socket.tcp(addr, port, connect_timeout: 2)&.close
      true
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET,
           Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
           SocketError, Timeout::Error
      false
    end
  end
end
