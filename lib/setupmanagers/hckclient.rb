# frozen_string_literal: true

require './lib/setupmanagers/exceptions'
require './lib/engines/hcktest/tests'
require './lib/engines/hcktest/targets'

# AutoHCK module
module AutoHCK
  # HCKClient class
  class HCKClient
    # Client cooldown timeout in seconds, to prevent hangs (30 minutes)
    CLIENT_COOLDOWN_TIMEOUT = 1800

    # Client cooldown sleep after thread is joined in seconds
    CLIENT_COOLDOWN_SLEEP = 60

    attr_reader :name, :kit
    attr_writer :support

    def initialize(setup_manager, scope, studio, name, run_opts)
      @project = setup_manager.project
      @logger = @project.logger
      @studio = studio
      @name = name
      @kit = setup_manager.kit
      @pool = 'Default Pool'
      @logger.info("Starting client #{name}")
      @runner = setup_manager.run_client(scope, @name, run_opts)
      scope << self
    end

    def keep_snapshot
      @runner.keep_snapshot
    end

    def add_target_to_project
      @target = Targets.new(self, @project, @tools, @pool).add_target_to_project
    end

    def run_tests
      @tests = Tests.new(self, @support, @project, @target, @tools)
      @tests.list_tests(log: true)
      @tests.run
    end

    def create_package
      @tests.create_project_package
    end

    def configure_machine
      move_machine_to_pool
      set_machine_ready
      sleep CLIENT_COOLDOWN_SLEEP
    end

    def reconfigure_machine
      delete_machine
      restart_machine
      return_when_client_up
      configure_machine
    end

    def delete_machine
      @tools.delete_machine(@name, @pool)
      @pool = 'Default Pool'
    end

    def restart_machine
      @logger.info("Restarting #{@name}")
      @tools.restart_machine(@name)
    end

    def move_machine_to_pool
      @logger.info("Moving #{@name} to pool")
      @tools.move_machine(@name, @pool, @project.engine.tag)
      @pool = @project.engine.tag
    end

    def set_machine_ready
      @logger.info("Setting #{@name} state to Ready")
      return if @tools.set_machine_ready(@name, @pool)

      raise ClientRunError, "Couldn't set #{@name} state to Ready"
    end

    def run_pre_test_commands
      @project.engine.drivers&.each do |driver|
        driver['pretestcommands']&.each do |command|
          desc = command['desc']
          cmd = command['run']

          @logger.info("Running command (#{desc}) on client #{@name}")
          @tools.run_on_machine(@name, desc, cmd)
        end
      end
    end

    def install_drivers
      path = @project.options.test.driver_path

      @project.engine.drivers&.each do |driver|
        method = driver['install_method']
        if method == 'no-drv'
          @project.logger.info("Driver installation skipped for #{driver['name']} in #{@name}")
          next
        end

        inf = driver['inf']

        @logger.info("Installing #{method} driver #{inf} in #{@name}")
        @tools.install_machine_driver_package(@name, path, method, inf,
                                              custom_cmd: driver['install_command'],
                                              sys_file: driver['sys'],
                                              force_install_cert: driver['install_cert'])
      end
    end

    def copy_dvl
      path = @project.options.test.driver_path

      @logger.info('Looking for DVL logs')
      Dir.glob("#{path}/*.DVL.XML", File::FNM_CASEFOLD).each do |dvl_file|
        dvl_file_name = File.basename(dvl_file)
        @logger.info("Uploading #{dvl_file_name} log to #{@name}")
        @tools.upload_to_machine(@name, dvl_file, "C:/DVL/#{dvl_file_name}")
      end
    end

    def machine_in_default_pool
      default_pool = @studio.list_pools
                            .detect { |pool| pool['name'].eql?('Default Pool') }

      default_pool['machines'].detect { |machine| machine['name'].eql?(@name) }
    end

    def recognize_client_wait
      @logger.info("Waiting for client #{@name} to be recognized")
      sleep 5 until machine_in_default_pool
      @logger.info("Client #{@name} recognized")
    end

    def initialize_client_wait
      @logger.info("Waiting for client #{@name} initialization")
      sleep 5 while machine_in_default_pool['state'].eql?('Initializing')
      @logger.info("Client #{@name} initialized")
    end

    def return_when_client_up
      recognize_client_wait
      initialize_client_wait
    end

    def configure(run_only: false)
      @tools = @studio.tools
      @cooldown_thread = Thread.new do
        return_when_client_up
        Thread.exit if run_only

        @logger.info("Preparing client #{@name}...")
        @project.extra_sw_manager.install_software_before_driver(@tools, @name)
        install_drivers
        copy_dvl
        @project.extra_sw_manager.install_software_after_driver(@tools, @name)
        @logger.info("Configuring client #{@name}...")
        configure_machine
        run_pre_test_commands
        add_target_to_project
      end
    end

    def synchronize
      return unless @cooldown_thread&.join(CLIENT_COOLDOWN_TIMEOUT).nil?

      e_message = "Timeout expired for the cooldown thread of client #{@name}"
      raise ClientRunError, e_message
    end

    def not_ready?
      @studio.list_pools.detect { |pool| pool['name'].eql?(@pool) }['machines']
             .detect { |machine| machine['name'].eql?(@name) }['state']
             .eql?('NotReady')
    end

    def reset_to_ready_state
      return unless not_ready?

      @logger.info("Setting client #{@name} state to Ready")
      set_machine_ready
    end

    def close
      @logger.info("Aborting HLKClient #{@name}")
      @cooldown_thread&.exit
    end
  end
end
