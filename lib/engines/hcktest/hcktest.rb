# frozen_string_literal: true

require './lib/setupmanagers/hckstudio'
require './lib/setupmanagers/hckclient'
require './lib/aux/json_helper'

# HCKTest class
class HCKTest
  PLATFORMS_JSON = 'lib/engines/hcktest/platforms.json'
  DRIVERS_JSON = 'drivers.json'
  # This is a temporary workaround for clients names
  CLIENTS = {
    CL1: 'c1',
    CL2: 'c2'
  }.freeze
  SM_RETRIES = 5

  def initialize(project)
    @project = project
    @platform = read_platform
    @driver = project.driver
    init_workspace
    @setup_manager = SetupManager.new(project)
    @studio = @setup_manager.create_studio
    initialize_clients
  end

  def init_workspace
    @workspace_path = [@project.workspace_path, @platform['name'],
                       @project.timestamp].join('/')
    begin
      FileUtils.mkdir_p(@workspace_path)
    rescue Errno::EEXIST
      @project.logger.warn('Workspace path already exists')
    end
    @project.move_workspace_to(@workspace_path.to_s)
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON, @project.logger)
    platform_name = @project.tag.split('-', 2).last
    @project.logger.info("Loading platform: #{platform_name}")
    res = platforms.find { |p| p['name'] == platform_name }
    @project.logger.fatal("#{platform_name} does not exist") unless res
    res || raise(InvalidConfigFile, "#{platform_name} does not exist")
  end

  def initialize_clients
    @clients = {}
    @platform['clients'].each do |name, client|
      @clients[client['name']] = @setup_manager.create_client(name,
                                                              client['name'])
    end
    return unless @clients.empty?

    raise InvalidConfigFile, 'Clients configuration for \
                              this platform is incorrect'
  end

  def synchronize_clients(exit: false)
    @clients.each_value do |client|
      client.synchronize(exit: exit)
    end
  end

  def configure_clients
    @clients.values.map(&:configure)
  end

  def configure_setup_and_synchronize
    @studio.configure(@platform['clients'])
    configure_clients
    synchronize_clients
    @client1 = @clients.values[0]
    @client2 = @clients.values[1]
    @client1.support = @client2
  end

  def run_clients
    @clients.values.map(&:run)
  end

  def clean_last_run_clients
    @clients.values.map(&:clean_last_run)
  end

  def clean_last_run_machines
    @studio.clean_last_run
    clean_last_run_clients
  end

  def run_and_configure_setup
    retries ||= 0
    Filelock '/var/tmp/virthck.lock', timeout: 0 do
      @studio.run
      run_clients
    end
    configure_setup_and_synchronize
  rescue AutoHCKError => e
    synchronize_clients(exit: true)
    @project.logger.warn("Running and configuring setup failed: (#{e.class}) "\
                       "#{e.message}")
    raise e unless (retries += 1) < AUTOHCK_RETRIES

    clean_last_run_machines
    @project.logger.info('Trying again to run and configure setup')
    retry
  end

  def run
    run_and_configure_setup
    client = @client1
    client.run_tests
    client.create_package
  end

  def close
    @clients.values.map(&:abort)
    @studio.abort
  end
end
