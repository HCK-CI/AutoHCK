# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # PhysHCK
  class PhysHCK
    # Runner is a class that represents a run.
    class Runner
      def initialize(logger)
        @logger = logger
      end

      def wait(...)
        @logger.info('Physical machine is always alive')
      end

      def keep_snapshot
        @logger.info('Keeping snapshot is currently not supported for physical machines')
      end

      def close
        @logger.info('Abort is currently not supported for physical machines')
      end
    end

    include Helper

    attr_reader :kit, :project

    PHYSHCK_CONFIG_JSON = 'lib/setupmanagers/physhck/physhck.json'

    def initialize(project)
      @project = project
      @logger = project.logger
      @platform = project.engine.platform
      @setup = find_setup
      @id = project.id
      @kit = @setup['kit']
    end

    def find_setup
      known_setups = Json.read_json(PHYSHCK_CONFIG_JSON, @logger)
      res = known_setups[@platform['name']]
      @project.logger.fatal("#{@platform['name']} does not exist") unless res
      res || raise(SetupManagerError, "#{@platform['name']} does not exist")
    end

    def check_studio_image_exist
      @logger.info('Image checking is currently not supported for physical machines')
    end

    def create_studio_image
      @logger.info('Image creating is currently not supported for physical machines')
    end

    def check_client_image_exist(_name)
      @logger.info('Image checking is currently not supported for physical machines')
    end

    def create_client_image(_name)
      @logger.info('Image creating is currently not supported for physical machines')
    end

    def run_studio(*)
      Runner.new(@logger)
    end

    def run_client(*)
      Runner.new(@logger)
    end

    def run_hck_studio(scope, run_opts)
      studio_ip = @setup['st_ip']
      HCKStudio.new(self, scope, run_opts) { studio_ip }
    end

    def run_hck_client(scope, studio, name, run_opts)
      HCKClient.new(self, scope, studio, name, run_opts)
    end
  end
end
