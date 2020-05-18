# frozen_string_literal: true

require './lib/engines/exceptions'
require './lib/setupmanagers/setupmanager'
require './lib/engines/hcktest/hcktest'

# Engine
#
class Engine
  class EngineFactory
    ENGINES = {
      hcktest: HCKTest
    }.freeze

    def self.create(type, project)
      ENGINES[type].new(project)
    end

    def self.can_create?(type)
      !ENGINES[type].nil?
    end
  end

  def initialize(project)
    @project = project
    @logger = project.logger
    @engine = nil
    @type = project.engine.downcase.to_sym
    engine_create
  end

  def engine_create
    if EngineFactory.can_create?(@type)
      @engine = EngineFactory.create(@type, @project)
    else
      @logger.warn("Unkown type engine #{@type}, Exiting...")
      raise InvalidEngineTypeError, "Unkown type engine #{@type}"
    end
  end
  
  def run
    @engine.run
  end

  def close
    @engine.close
  end
end
