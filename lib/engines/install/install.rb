# frozen_string_literal: true

# Install class
class Install
  def initialize(project)
    @project = project
    @logger = project.logger
    @logger.info("Install: initialized")
  end

  def run
    @logger.info("Install: run")
  end

  def close
    @logger.info("Install: close")
  end
end
