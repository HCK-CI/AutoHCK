# frozen_string_literal: true

require './lib/exceptions'
require './lib/auxiliary/json_helper'

# PhysHCK
class PhysHCK
  attr_reader :kit
  PHYSHCK_CONFIG_JSON = 'lib/setupmanagers/physhck/physhck.json'
  PLATFORMS_JSON = 'lib/engines/hcktest/platforms.json'

  def initialize(project)
    @project = project
    @logger = project.logger
    @platform = read_platform
    @setup = find_setup
    @id = project.id
    @kit = @setup['kit']
  end

  def find_setup
    known_setups = read_json(PHYSHCK_CONFIG_JSON, @logger)
    res = known_setups.find { |setup| setup['name'] == @platform['name'] }
    @project.logger.fatal("#{@platform['name']} does not exist") unless res
    res || raise(SetupManagerError, "#{@platform['name']} does not exist")
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON, @project.logger)
    platform_name = @project.tag.split('-', 2).last
    res = platforms.find { |p| p['name'] == platform_name }
    @project.logger.fatal("#{platform_name} does not exist") unless res
    res || raise(SetupManagerError, "#{platform_name} does not exist")
  end

  def create_studio_snapshot
    @logger.info('Snapshots are currently not supported for physical machines')
  end

  def delete_studio_snapshot
    @logger.info('Snapshots are currently not supported for physical machines')
  end

  def create_client_snapshot(_name)
    @logger.info('Snapshots are currently not supported for physical machines')
  end

  def delete_client_snapshot(_name)
    @logger.info('Snapshots are currently not supported for physical machines')
  end

  def run(*)
    # Physical = no pid
    -1
  end

  def create_studio
    studio_ip = @setup['st_ip']
    @studio = HCKStudio.new(@project, self, 'st', studio_ip)
  end

  def create_client(tag, name)
    HCKClient.new(@project, self, @studio, tag, name)
  end

  def close
    @logger.info('Closing setup manager')
  end
end
