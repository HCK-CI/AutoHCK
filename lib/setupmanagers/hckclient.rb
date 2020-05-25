# frozen_string_literal: true

require './lib/setupmanagers/excpetions'
require './lib/engines/hcktest/tests'
require './lib/engines/hcktest/targets'

# HCKClient class
class HCKClient < Machine
  attr_reader :name, :id, :kit
  attr_writer :support
  def initialize(project, setupmanager, studio, tag, name)
    @id = tag[-1]
    super(project, name, setupmanager, @id, tag)
    @studio = studio
    @kit = setupmanager.kit
    @pool = 'Default Pool'
  end

  def create_snapshot
    @setupmanager.create_client_snapshot(@tag)
  end

  def delete_snapshot
    @setupmanager.delete_client_snapshot(@tag)
  end

  def run
    create_snapshot
    super
  end

  def add_target_to_project
    @target = Targets.new(self, @project, @tools, @pool).add_target_to_project
  end

  def run_tests
    @tests = Tests.new(self, @support, @project, @target, @tools)
    @tests.list_tests
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
    @tools.move_machine(@name, @pool, @project.tag)
    @pool = @project.tag
  end

  def set_machine_ready
    @logger.info("Setting #{@name} state to Ready")
    return if @tools.set_machine_ready(@name, @pool)

    raise ClientRunError, "Couldn't set #{@name} state to Ready"
  end

  def run_pre_test_commands
    @project.driver['pretestcommands']&.each do |command|
      desc = command['desc']
      cmd = command['run']

      @logger.info("Running command (#{desc}) on client #{@name}")
      @tools.run_on_machine(@name, desc, cmd)
    end
  end

  def install_driver
    method = @project.driver['install_method']
    path = @project.driver_path
    inf = @project.driver['inf']
    @logger.info("Installing #{method} driver #{inf} in #{@name}")
    @tools.install_machine_driver_package(@name, path, method, inf)
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

  # Client cooldown timeout in seconds, to prevent hangs (30 minutes)
  CLIENT_COOLDOWN_TIMEOUT = 1800

  # Client cooldown sleep after thread is joined in seconds
  CLIENT_COOLDOWN_SLEEP = 60

  def configure
    @tools = @studio.tools
    @cooldown_thread = Thread.new do
      return_when_client_up
      install_driver
      @logger.info("Configuring client #{@name}...")
      configure_machine
      run_pre_test_commands
      add_target_to_project
    end
  end

  def synchronize(exit: false)
    if exit
      @cooldown_thread&.exit
    else
      return unless @cooldown_thread&.join(CLIENT_COOLDOWN_TIMEOUT).nil?

      e_message = "Timeout expired for the cooldown thread of client #{@name}"
      raise ClientRunError, e_message
    end
  end

  def not_ready?
    @studio.list_pools.detect { |pool| pool['name'].eql?(@pool) }['machines']\
           .detect { |machine| machine['name'].eql?(@name) }['state']\
           .eql?('NotReady')
  end

  def reset_to_ready_state
    return unless not_ready?

    @logger.info("Setting client #{@name} state to Ready")
    set_machine_ready
  end

  def keep_alive
    return if alive?

    @logger.info("Starting client #{@name}")
    @pid = @setup_manager.run(@tag)
    e_message = "Client #{@name} new PID could not be retrieved"
    raise ClientRunError, e_message unless @pid

    @logger.info("Client #{@name} new PID is #{@pid}")
    raise ClientRunError, "Could not start client #{@name}" unless alive?
  rescue CmdRunError
    raise ClientRunError, "Could not start client #{@name}"
  end
end
