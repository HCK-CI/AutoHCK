# frozen_string_literal: true

require './lib/exceptions'

# targets class
class Targets
  TARGET_RETIRES = 5
  def initialize(client, project, tools, pool)
    @machine = client.name
    @client = client
    @project = project
    @name = project.device['name']
    @tools = tools
    @pool = pool
    @logger = project.logger
  end

  # A custom AddTargetToProjec error exception
  class AddTargetToProjectError < AutoHCKError; end

  def add_target_to_project
    retries ||= 0
    tag = @project.tag
    target = search_target
    @logger.info("Adding target #{@name} on #{@machine} to project #{tag}")
    return target if @tools.create_project_target(target['key'], tag, @machine)

    e_message = "Adding target #{@name} on #{@machine} to project #{tag} failed"
    raise AddTargetToProjectError, e_message
  rescue AddTargetToProjectError => e
    @logger.warn(e.message)
    raise unless (retries += 1) < TARGET_RETIRES

    @logger.info("Reconfiguring client #{@machine}...")
    @client.reconfigure_machine
    @logger.info("Trying again to add target #{@name} on #{@machine} to "\
                 "project #{tag}")
    retry
  end

  def search_target
    @logger.info("Searching for target #{@name} on #{@machine}")
    @tools.list_machine_targets(@machine, @pool).each do |target|
      return target if target['name'].eql?(@name)
    end

    raise AddTargetToProjectError, "Target #{@name} not found on #{@machine}"
  end
end
