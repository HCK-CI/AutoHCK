# frozen_string_literal: true

require 'rtoolsHCK'
require 'net/ping'
require './lib/tools'
require './lib/exceptions'
# Studio class
class Studio
  attr_reader :tools, :name, :id
  HCK_FILTERS_PATH = 'filters/UpdateFilters.sql'
  def initialize(project, setup_manager, name)
    @name = name
    @id = 0
    @project = project
    @logger = project.logger
    @setup_manager = setup_manager
  end

  # A custom StudioConnect error exception
  class StudioConnectError < AutoHCKError; end

  # A custom StudioRun error exception
  class StudioRunError < AutoHCKError; end

  def up?
    check = Net::Ping::External.new(@ip)
    check.ping?
  end

  def create_snapshot
    @setup_manager.create_studio_snapshot
  end

  def delete_snapshot
    @setup_manager.delete_studio_snapshot
  end

  def create_pool
    @logger.info('Creating pool')
    tag = @project.tag
    @tools.create_pool(tag)
  end

  def create_project
    @logger.info('Creating project')
    tag = @project.tag
    @tools.create_project(tag)
  end

  def list_pools
    @tools.list_pools
  end

  def update_filters
    return unless File.file?(HCK_FILTERS_PATH)

    @logger.info('Updating HCK filters')
    @tools.update_filters(HCK_FILTERS_PATH)
  end

  CONNECT_RETRIES = 5
  CONNECT_RETRY_SLEEP = 10

  def connect
    retries ||= 0
    begin
      @logger.info('Initiating connection to studio')
      @tools = Tools.new(@project, @ip, @clients)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, RToolsHCKConnectionError
      raise StudioConnectError, 'Initiating connection to studio failed'
    end
  rescue StudioConnectError => e
    @logger.warn(e.message)
    raise unless (retries + 1) < CONNECT_RETRIES

    sleep CONNECT_RETRY_SLEEP
    @logger.info('Trying again to initiate connection to studio')
    retry
  end

  def verify_tools
    return if @tools.connection_check

    raise StudioConnectError, 'Tools did not pass the connection check'
  end

  def run
    create_snapshot
    @logger.info('Starting studio')
    @ip = @project.config['ip_segment'] + @project.id.to_str
    @pid = @setup_manager.run(@name, true)
    raise StudioRunError, 'Studio PID could not be retrieved' unless @pid

    @logger.info("Studio PID is #{@pid}")
    @monitor = Monitor.new(@project, self)
    raise StudioRunError, 'Could not start studio' unless alive?
  rescue CmdRunError
    raise StudioRunError, 'Could not start studio'
  end

  def clean_last_run
    @logger.info('Cleaning last studio run')
    @tools&.close
    @tools = nil
    unless hard_abort
      @logger.info('Studio hard abort failed, force aborting...')
      Process.kill('KILL', @pid)
    end
    delete_snapshot
  end

  def configure(clients)
    @clients = clients
    @logger.info('Waiting for studio to load...')
    sleep 5 until up?
    connect
    verify_tools
    update_filters
    create_pool
    create_project
  end

  def poweroff
    @monitor&.powerdown
  end

  # Studio soft abort trials before force abort
  ABORT_RETRIES = 10

  # Studio soft abort sleep for each trial
  ABORT_SLEEP = 30

  def soft_abort
    ABORT_RETRIES.times do
      return true unless alive?

      poweroff
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
    @tools&.close

    @logger.info('Studio soft abort failed, hard aborting...')
    return if hard_abort

    @logger.info('Studio hard abort failed, force aborting...')
    Process.kill('KILL', @pid)
  end

  def shutdown
    @logger.info('Shutting down studio')
    @tools.shutdown
  end

  def alive?
    return false unless @pid

    Process.kill(0, @pid)
    true
  rescue Errno::ESRCH
    @logger.info('Studio is not alive')
    false
  end
end
