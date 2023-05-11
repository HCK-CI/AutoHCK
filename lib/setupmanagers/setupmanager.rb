# frozen_string_literal: true

require './lib/exceptions'
require './lib/setupmanagers/physhck/physhck'
require './lib/setupmanagers/qemuhck/qemuhck'

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
      @type = project.config['setupmanager'].downcase.to_sym
      setupmanager_create
    end

    def setupmanager_create
      if SetupManagerFactory.can_create?(@type)
        @setupmanager = SetupManagerFactory.create(@type, @project)
      else
        @logger.warn("Unkown type setup manager #{@type}, Exiting...")
        raise SetupManagerError, "Unkown type setup manager #{@type}"
      end
    end

    def check_studio_image_exist
      @setupmanager.check_studio_image_exist
    end

    def create_studio_image
      @setupmanager.create_studio_image
    end

    def check_client_image_exist(name)
      @setupmanager.check_client_image_exist(name)
    end

    def create_client_image(name)
      @setupmanager.create_client_image(name)
    end

    def studio_option_config(option)
      @setupmanager.studio_option_config(option)
    end

    def client_option_config(name, option)
      @setupmanager.client_option_config(name, option)
    end

    def run(name, run_opts = {})
      @setupmanager.run(name, run_opts)
    end

    def studio_alive?
      @setupmanager.studio_alive?
    end

    def client_alive?(name)
      @setupmanager.client_alive?(name)
    end

    def keep_studio_alive
      @setupmanager.keep_studio_alive
    end

    def keep_client_alive(name)
      @setupmanager.keep_client_alive(name)
    end

    def clean_last_studio_run
      @setupmanager.clean_last_studio_run
    end

    def clean_last_client_run(name)
      @setupmanager.clean_last_client_run(name)
    end

    def create_studio
      @setupmanager.create_studio
    end

    def create_client(name)
      @setupmanager.create_client(name)
    end

    def abort_studio
      @setupmanager.abort_studio
    end

    def abort_client(name)
      @setupmanager.abort_client(name)
    end

    def close
      @setupmanager.close
    end
  end
end
