# frozen_string_literal: true

require './lib/exceptions'

# AutoHCK module
module AutoHCK
  # targets class
  class Targets
    TARGET_RETIRES = 5
    def initialize(client, project, tools, pool)
      @machine = client.name
      @client = client
      @project = project
      @name = project.engine.target['name']
      @type = project.engine.target['type']
      @tools = tools
      @pool = pool
      @logger = project.logger
    end

    # A custom Target error exception
    class TargetError < AutoHCKError; end

    # A custom AddTargetToProjec error exception
    class AddTargetToProjectError < TargetError; end

    # A custom SearchTarget error exception
    class SearchTargetError < TargetError; end

    def add_target_to_project
      retries ||= 0
      tag = @project.tag
      target = search_target
      @logger.info("Adding target #{@name} on #{@machine} to project #{tag}")
      return target if @tools.create_project_target(target['key'], tag, @machine)

      e_message = "Adding target #{@name} on #{@machine} to project #{tag} failed"
      raise AddTargetToProjectError, e_message
    rescue TargetError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < TARGET_RETIRES

      @logger.info("Reconfiguring client #{@machine}...")
      @client.reconfigure_machine
      @logger.info("Trying again to add target #{@name} on #{@machine} to "\
                  "project #{tag}")
      retry
    end

    def search_target
      @logger.info("Searching for target #{@name} (type #{@type}) on #{@machine}")
      target_list = @tools.list_machine_targets(@machine, @pool)
      @logger.debug("Received target list: #{target_list}")
      target_list.each do |target|
        return target if target['name'].eql?(@name) && target['type'].eql?(@type)
      end

      raise SearchTargetError, "Target #{@name} not found on #{@machine}"
    end
  end
end
