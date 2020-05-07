# frozen_string_literal: true

require './lib/exceptions'
require './setupmanagers/setupmanager'
require './lib/id_gen'
require './engines/hcktest'

# Engine
#
class Engine
  attr_reader :id
=begin
  # EngineSettings
  #
  class EngineParams
    def initialize(device, platform, workspace_path, id)
      @device = device
      @platform = platform
      @workspace_path = workspace_path
      @id = id
    end
  end
=end
  # EngineFactory
  #
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
=begin
  def create_studio_snapshot
    @engine.create_studio_snapshot
  end

  def delete_studio_snapshot
    @engine.delete_studio_snapshot
  end

  def create_client_snapshot(name)
    @engine.create_client_snapshot(name)
  end

  def delete_client_snapshot(name)
    @engine.delete_client_snapshot(name)
  end
=end
  def run
    @engine.run
  end

  def close
    @engine.close
  end
end
