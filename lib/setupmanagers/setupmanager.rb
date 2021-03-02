# frozen_string_literal: true

require './lib/exceptions'
require './lib/setupmanagers/virthck/virthck'
require './lib/setupmanagers/physhck/physhck'

# AutoHCK module
module AutoHCK
  # SetupManager
  #
  class SetupManager
    attr_reader :id

    # SetupManagerFactory
    #
    class SetupManagerFactory
      SETUP_MANAGERS = {
        virthck: VirtHCK,
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
      @type = project.config['setupmanager'].downcase.to_sym
      setupmanager_create
    end

    def setupmanager_create
      if SetupManagerFactory.can_create?(@type)
        @setupmanager = SetupManagerFactory.create(@type, @project)
      else
        @logger.warn("Unkown type setup mainager #{@type}, Exiting...")
        raise SetupManagerError, "Unkown type setup manager #{@type}"
      end
    end

    def check_studio_image_exist
      @setupmanager.check_studio_image_exist
    end

    def create_studio_image
      @setupmanager.create_studio_image
    end

    def create_studio_snapshot
      @setupmanager.create_studio_snapshot
    end

    def delete_studio_snapshot
      @setupmanager.delete_studio_snapshot
    end

    def check_client_image_exist(name)
      @setupmanager.check_client_image_exist(name)
    end

    def create_client_image(name)
      @setupmanager.create_client_image(name)
    end

    def create_client_snapshot(name)
      @setupmanager.create_client_snapshot(name)
    end

    def delete_client_snapshot(name)
      @setupmanager.delete_client_snapshot(name)
    end

    def run(name, run_opts = {})
      @setupmanager.run(name, run_opts)
    end

    def create_studio
      @setupmanager.create_studio
    end

    def create_client(tag, name)
      @setupmanager.create_client(tag, name)
    end

    def close
      @setupmanager.close
    end
  end
end
