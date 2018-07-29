require 'rtoolsHCK'
require 'net/ping'
require './lib/tools'

# Studio class
class Studio
  attr_reader :tools
  def initialize(project, name)
    @name = name
    @project = project
    @logger = project.logger
    @virthck = project.virthck
    @id = project.virthck.id
    @ip = project.config['ip_segment'] + @id
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

  def connect
    @logger.info('Initiating connection to studio')
    @tools = Tools.new(@project, @ip)
  end

  def run
    @logger.info('Starting studio')
    @virthck.run(@name, true)
    sleep 2 until up?
  end

  def shutdown
    @logger.info('Shutting down studio')
    @tools.shutdown
  end

  def close
    @virthck.close
  end
end
