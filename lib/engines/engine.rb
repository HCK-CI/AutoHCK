# frozen_string_literal: true

require './lib/engines/exceptions'
require './lib/setupmanagers/setupmanager'
require './lib/engines/hcktest/hcktest'
require './lib/engines/hckinstall/hckinstall'

# AutoHCK module
module AutoHCK
  # Engine Class
  #
  class Engine
    # EngineFactory Class
    #
    class EngineFactory
      ENGINES = {
        hcktest: HCKTest,
        hckinstall: HCKInstall
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
      @type = project.engine_type.downcase.to_sym
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

    def tag
      @engine.tag
    end

    def config
      @engine.config
    end

    def run
      @engine.run
    end

    def drivers
      @engine.drivers
    end

    def target
      @engine.target
    end

    def platform
      @engine.platform
    end

    def result_uploader_needed?
      @engine.result_uploader_needed?
    end

    def close
      @engine.close
    end
  end
end
