# frozen_string_literal: true

require './lib/exceptions'
require './lib/virthck'
require './lib/id_gen'

# Engine
#
class Engine
  attr_reader :id
  # EngineFactory
  #
  class EngineFactory
    ENGINES = {
      virthck: VirtHCK
    }.freeze

    def self.create(type, project, id)
      ENGINES[type].new(project, id)
    end

    def self.can_create?(type)
      !ENGINES[type].nil?
    end
  end

  def initialize(project)
    @project = project
    @logger = project.logger
    @config = project.config
    @engine = nil
    @type = @config['engine'].to_sym
    engine_create
  rescue InvalidPathError
    release_id
    exit(1)
  end

  def engine_create
    if EngineFactory.can_create?(@type)
      @id_gen = Idgen.new(@project)
      @id = assign_id
      @engine = EngineFactory.create(@type, @project, @id)
    else
      @project.logger.warn("Unkown type engine #{@type}, Exiting...")
      exit
    end
  end

  def assign_id
    @id = @id_gen.allocate
    while @id.negative?
      @logger.info('No available ID')
      sleep 20
      @id = @id_gen.allocate
    end
    @logger.info("Assinged ID: #{@id}")
    @id.to_s
  end

  def release_id
    @logger.info("Releasing ID: #{@id}")
    @id_gen.release(@id)
  end

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

  def run(name, first_time = false)
    @engine.run(name, first_time)
  end

  def close
    @engine.close
  end
end
