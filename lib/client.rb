require 'net/ping'
require './lib/tests'
require './lib/targets'
require './lib/monitor'
require './lib/github'
require './lib/virthck'

# Client class
class Client
  attr_reader :machine, :name, :id

  def initialize(project, studio, name)
    @name = name
    @id = name[-1]
    @pool = 'Default Pool'
    @project = project
    @logger = project.logger
    @studio = studio
    @virthck = project.virthck
    create_snapshot
  end

  def create_snapshot
    @virthck.create_client_snapshot(@name)
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

  def setup_driver
    install_driver
    reconfigure_machine
  end

  def reconfigure_machine
    delete_machine
    restart_machine
    return_client_when_up
    move_machine_to_pool
    set_machine_ready
  end

  def delete_machine
    @tools.delete_machine(@machine['name'], @pool)
    @pool = 'Default Pool'
  end

  def restart_machine
    @logger.info("Restarting #{@machine['name']}")
    @tools.restart_machine(@machine['name'])
  end

  def shutdown_machine
    @monitor.powerdown
  end

  def abort
    loop do
      return unless client_alive?

      shutdown_machine
    end
  end

  def move_machine_to_pool
    @logger.info("Moving #{@machine['name']} to pool")
    @tools.move_machine(@machine['name'], @pool, @project.tag)
    @pool = @project.tag
  end

  def set_machine_ready
    @tools.set_machine_ready(@machine['name'], @pool)
  end

  def install_driver
    method = @project.device['install_method']
    name = @machine['name']
    path = @project.driver_path
    inf = @project.device['inf']
    @logger.info("Installing #{method} driver #{inf} in #{name}")
    @tools.install_machine_driver_package(name, path, method, inf)
  end

  def default_pool_machines
    @studio.list_pools.first['machines']
  end

  def recognize_client_wait
    count = default_pool_machines.count
    @logger.info('Waiting for client to be recognized')
    sleep 5 while default_pool_machines.count == count
    @logger.info('Client recognized')
  end

  def initialize_client_wait
    @logger.info('Waiting for client initialization')
    sleep 5 while default_pool_machines.last['state'] == 'Initializing'
    sleep 80
    @logger.info('Client initialized')
  end

  # Client up timeout is seconds, to prevent hangs (30 minutes)
  CLIENT_UP_TIMEOUT = 1800

  def return_client_when_up
    Timeout.timeout(CLIENT_UP_TIMEOUT) do
      recognize_client_wait
      initialize_client_wait
      default_pool_machines.last
    end
  rescue Timeout::Error
    @logger.info('Timeout expired while waiting for client up,'\
                 'restarting using client\'s QEMU monitor')
    @monitor.reset
    retry
  end

  def run
    @tools = @studio.tools
    @logger.info('Starting client')
    @virthck.run(@name, true)
    @monitor = Monitor.new(@project, self)
    @machine = return_client_when_up
  end

  def keep_alive
    @virthck.run(@name) unless client_alive?
  end

  def client_alive?
    @virthck.client_alive?(@name)
  end
end
