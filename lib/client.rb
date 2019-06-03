# frozen_string_literal: true

require 'net/ping'
require './lib/tests'
require './lib/targets'
require './lib/monitor'
require './lib/github'
require './lib/virthck'

# Client class
class Client
  attr_reader :name, :id
  def initialize(project, studio, tag)
    @tag = tag
    @id = tag[-1]
    @pool = 'Default Pool'
    @project = project
    @logger = project.logger
    @name = @project.platform['clients'][tag]['name']
    @studio = studio
    @virthck = project.virthck
    create_snapshot
  end

  # A custom ClientRun error exception
  class ClientRunError < AutoHCKError; end

  def create_snapshot
    @virthck.create_client_snapshot(@tag)
  end

  def add_target_to_project
    targets = Targets.new(self, @project, @tools, @pool)
    @target = targets.add_target_to_project
  end

  def add_support(support)
    @support = support
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
    @logger.info("Configuring client #{@name}...")
    move_machine_to_pool
    set_machine_ready
  end

  def reconfigure_machine
    @logger.info("Reconfiguring client #{@name}...")
    delete_machine
    restart_machine
    return_when_client_up
    move_machine_to_pool
    set_machine_ready
  end

  def delete_machine
    @tools.delete_machine(@name, @pool)
    @pool = 'Default Pool'
  end

  def restart_machine
    @logger.info("Restarting #{@name}")
    @tools.restart_machine(@name)
  end

  def shutdown_machine
    @monitor&.powerdown
  end

  # Client soft abort trials before force abort
  ABORT_RETRIES = 10

  # Client soft abort sleep for each trial
  ABORT_SLEEP = 30

  def soft_abort
    ABORT_RETRIES.times do
      return true unless alive?

      shutdown_machine
      sleep ABORT_SLEEP
    end
    false
  end

  def hard_abort
    @monitor&.quit
    sleep ABORT_SLEEP
    return true unless alive?

    false
  end

  def abort
    return if soft_abort

    @logger.info("Client #{@name} soft abort failed, hard aborting...")
    return if hard_abort

    @logger.info("Client #{@name} hard abort failed, force aborting...")
    Process.kill('KILL', @pid)
  end

  def move_machine_to_pool
    @logger.info("Moving #{@name} to pool")
    @tools.move_machine(@name, @pool, @project.tag)
    @pool = @project.tag
  end

  def set_machine_ready
    @logger.info("Setting #{@name} state to Ready")
    @tools.set_machine_ready(@name, @pool)
  end

  def install_driver
    method = @project.device['install_method']
    path = @project.driver_path
    inf = @project.device['inf']
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

  # Client up timeout is seconds, to prevent hangs (30 minutes)
  CLIENT_UP_TIMEOUT = 1800

  def return_when_client_up
    retries ||= 0
    Timeout.timeout(CLIENT_UP_TIMEOUT) do
      recognize_client_wait
      initialize_client_wait
    end
  rescue Timeout::Error
    @logger.info('Timeout expired while waiting for client up,'\
                 'restarting using client\'s QEMU monitor')
    @monitor.reset
    retry if (retries += 1) < 3
    raise FatalClientError.new(@name), "Client #{@name} couldn't be recognized"
  end

  def run
    @logger.info("Starting client #{@name}")
    @pid = @virthck.run(@tag, true)
    e_message = "Client #{@name} PID could not be retrieved"
    raise ClientRunError, e_message unless @pid

    @logger.info("Client #{@name} PID is #{@pid}")
    @monitor = Monitor.new(@project, self)
    raise ClientRunError, "Could not start client #{@name}" unless alive?
  rescue VirtHCK::CmdRunError
    raise ClientRunError, "Could not start client #{@name}"
  end

  def configure
    @tools = @studio.tools
    @cooldown_thread = Thread.new do
      return_when_client_up
      install_driver
      @logger.info("Configuring client #{@name}...")
      configure_machine
      add_target_to_project
    end
  end

  def synchronize
    @cooldown_thread&.join
  end

  def not_ready?
    @studio.list_pools.detect { |pool| pool['name'].eql?(@pool) }['machines']\
           .detect { |machine| machine['name'].eql?(@name) }['state']\
           .eql?('NotReady')
  end

  def alive?
    return false unless @pid

    Process.kill(0, @pid)
    true
  rescue Errno::ESRCH
    @logger.info("Client #{@name} is not alive")
    false
  end

  def reset_to_ready_state
    return unless not_ready?

    @logger.info("Setting client #{@name} state to Ready")
    set_machine_ready
  end

  def keep_alive
    return if alive?

    @logger.info("Starting client #{@name}")
    @pid = @virthck.run(@tag)
    e_message = "Client #{@name} new PID could not be retrieved"
    raise ClientRunError, e_message unless @pid

    @logger.info("Client #{@name} new PID is #{@pid}")
    raise ClientRunError, "Could not start client #{@name}" unless alive?
  rescue VirtHCK::CmdRunError
    raise ClientRunError, "Could not start client #{@name}"
  end
end
