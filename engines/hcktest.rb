# frozen_string_literal: true

require './lib/studio'
require './lib/client'
require './lib/json-helper'

# HCKTest class
class HCKTest

  PLATFORMS_JSON = 'platforms.json'
  DRIVERS_JSON = 'drivers.json'
  STUDIO = 'st'
  # This is a temporary workaround for clients names
  CLIENTS =  {
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
    @studio = Studio.new(@project, @setup_manager, STUDIO)
    initialize_clients
  end

  def init_workspace
    @workspace_path = [@project.workspace_path,@platform['name']].join('/')
    begin
      FileUtils.mkdir_p(@workspace_path)
    rescue Errno::EEXIST
      @project.logger.warn('Workspace path already exists')
    end
    @project.move_workspace_to("#{@workspace_path}")
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON, @project.logger)
    platform_name = @project.tag.split('-', 2).last
    @project.logger.info("Loading platform: #{platform_name}")
    res = platforms.find { |p| p['name'] == platform_name }
    @project.logger.fatal("#{platform_name} does not exist") unless res
    res || exit(1)
  end

  def initialize_clients
    @clients = {}
    @platform['clients'].each_value do |client|
      @project.logger.info(client['name'])
      tag = CLIENTS[client['name'].to_sym]
      @clients[client['name']] = HCKClient.new(@project, @setup_manager, @studio, tag,@platform['clients'][tag]['name'], @platform['kit'])
    end
    if @clients.empty?
      raise InvalidConfigFile,'Clients configuration for this platform is incorrect'
    end
  end

  def synchronize_clients(exit: false)
    @clients.each_value do |client|
      client.synchronize(exit)
    end
  end

  def configure_setup_manager_and_synchronize
    @studio.configure(@platform['clients'])
    @clients.each_value do |client|
      client.configure
    end
    @clients.each_value do |client|
      client.synchronize
    end
    @client1 = @clients.values[0]
    @client2 = @clients.values[1]
    @client1.support = @client2 
  end

  def run_clients
     @clients.each_value do |client|
       client.run
     end
  end

  def clean_last_run_machines
    @studio.clean_last_run
    @client1.clean_last_run
    @client2.clean_last_run
  end

  def run_and_configure_setup_manager
    retries ||= 0
    Filelock '/var/tmp/virthck.lock', timeout: 0 do
      @studio.run
      run_clients
    end
    configure_setup_manager_and_synchronize
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
    run_and_configure_setup_manager
    client = @client1
    client.run_tests
    client.create_package
  end

  def close
    @clients.each_value do |client|
       client.abort
    end
    @studio.abort
  end
end
