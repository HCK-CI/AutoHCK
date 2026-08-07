# frozen_string_literal: true

module AutoHCK
  # Client for the installtest engine.
  #
  # Identical to FunctestClient except prepare_machine skips driver
  # installation — the driver was already installed during OS setup
  # via the answer file DriverPaths directive.
  class InstallTestClient < FunctestClient
    def prepare_machine(tools)
      @logger.info("Preparing installtest client #{@name} (no driver install)...")
      @tools = tools
      @tools.wait_for_client_online(@name)
      @project.extra_sw_manager.install_software_before_driver(@tools, @name)
      copy_test_binaries
      @project.extra_sw_manager.install_software_after_driver(@tools, @name)
    end
  end
end
