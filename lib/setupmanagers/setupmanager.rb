# frozen_string_literal: true

require './lib/exceptions'
require './lib/setupmanagers/physhck/physhck'
require './lib/setupmanagers/qemuhck/qemuhck'

# AutoHCK module
module AutoHCK
  # SetupManager
  #
  class SetupManager < SimpleDelegator
    attr_reader :id

    # SetupManagerFactory
    #
    class SetupManagerFactory
      SETUP_MANAGERS = {
        qemuhck: QemuHCK,
        physhck: PhysHCK
      }.freeze

      def self.create(type, project)
        SETUP_MANAGERS[type].new(project)
      end

      def self.can_create?(type)
        !SETUP_MANAGERS[type].nil?
      end
    end

    def initialize(project)
      @project = project
      @logger = project.logger
      @type = project.engine.platform['setupmanager'].downcase.to_sym
      super(setupmanager_create)
    end

    def setupmanager_create
      if SetupManagerFactory.can_create?(@type)
        SetupManagerFactory.create(@type, @project)
      else
        @logger.warn("Unkown type setup manager #{@type}, Exiting...")
        raise SetupManagerError, "Unkown type setup manager #{@type}"
      end
    end
  end
end
