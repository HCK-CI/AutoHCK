require 'rtoolsHCK'
require 'net/ping'
require './lib/tools'

# Studio class
class Studio
  attr_reader :tools, :name, :id
  HCK_FILTERS_PATH = 'filters/UpdateFilters.sql'.freeze
  def initialize(project, name)
    @name = name
    @id = 0
    @project = project
    @logger = project.logger
    @virthck = project.virthck
    create_snapshot
  end

  def up?
    check = Net::Ping::External.new(@ip)
    check.ping?
  end

  def create_snapshot
    @virthck.create_studio_snapshot
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

  def connect
    @logger.info('Initiating connection to studio')
    @tools = Tools.new(@project, @ip)
  end

  def assign_id
    @ip = @project.config['ip_segment'] + @virthck.id
  end

  def run
    @logger.info('Starting studio')
    assign_id
    @pid = @virthck.run(@name, true)
    if @pid
      @logger.info("Studio PID is #{@pid}")
    else
      @logger.error('Studio PID could not be retrieved')
    end
    @monitor = Monitor.new(@project, self)
    raise 'Could not start studio' unless @virthck.studio_alive?
  end

  def configure
    @logger.info('Waiting for studio to load...')
    sleep 5 until up?
    connect
    update_filters
    create_pool
    create_project
  end

  def poweroff
    @monitor.powerdown if @monitor
  end

  def abort
    loop do
      break unless @virthck.studio_alive?

      poweroff
      sleep 5
    end
    @logger.info("Studio #{@name} is offline")
  end

  def shutdown
    @logger.info('Shutting down studio')
    @tools.shutdown
  end
end
