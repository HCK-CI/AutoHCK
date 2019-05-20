# frozen_string_literal: true

# targets class
class Targets
  def initialize(client, project, tools, pool)
    @machine = client.name
    @client = client
    @project = project
    @tools = tools
    @pool = pool
    @logger = project.logger
  end

  def add_target_to_project
    tag = @project.tag
    target = search_target
    key = target['key']
    @tools.create_project_target(key, tag, @machine)
    target
  end

  def search_target
    target_name = @project.device['name']
    @logger.info("Searching for target #{target_name}")
    list_targets.each do |target|
      return target if target['name'].include?(target_name)
    end
    @logger.fatal('Target not found')
    raise 'target not found'
  rescue StandardError
    @client.reconfigure_machine
    retry
  end

  def list_targets
    @logger.info("listing targets of #{@machine}")
    @tools.list_machine_targets(@machine, @pool)
  end
end
