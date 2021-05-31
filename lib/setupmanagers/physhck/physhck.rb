# frozen_string_literal: true

require './lib/exceptions'
require './lib/auxiliary/json_helper'

# AutoHCK module
module AutoHCK
  # PhysHCK
  class PhysHCK
    include Helper

    attr_reader :kit

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
      known_setups = read_json(PHYSHCK_CONFIG_JSON, @logger)
      res = known_setups.find { |setup| setup['name'] == @platform['name'] }
      @project.logger.fatal("#{@platform['name']} does not exist") unless res
      res || raise(SetupManagerError, "#{@platform['name']} does not exist")
    end

    def check_studio_image_exist
      @logger.info('Image checking is currently not supported for physical machines')
    end

    def create_studio_image
      @logger.info('Image creating is currently not supported for physical machines')
    end

    def create_studio_snapshot
      @logger.info('Snapshots are currently not supported for physical machines')
    end

    def delete_studio_snapshot
      @logger.info('Snapshots are currently not supported for physical machines')
    end

    def check_client_image_exist(_name)
      @logger.info('Image checking is currently not supported for physical machines')
    end

    def create_client_image(_name)
      @logger.info('Image creating is currently not supported for physical machines')
    end

    def create_client_snapshot(_name)
      @logger.info('Snapshots are currently not supported for physical machines')
    end

    def delete_client_snapshot(_name)
      @logger.info('Snapshots are currently not supported for physical machines')
    end

    def run(*)
      # Physical = no pid
      -1
    end

    def studio_alive?
      @logger.info('Physical machine is always alive')
    end

    def client_alive?(_name)
      @logger.info('Physical machine is always alive')
    end

    def keep_studio_alive
      @logger.info('Physical machine is always alive')
    end

    def keep_client_alive(_name)
      @logger.info('Physical machine is always alive')
    end

    def clean_last_studio_run
      @logger.info('Clean last run is currently not supported for physical machines')
    end

    def clean_last_client_run(_name)
      @logger.info('Clean last run is currently not supported for physical machines')
    end

    def create_studio
      studio_ip = @setup['st_ip']
      @studio = HCKStudio.new(@project, self, 'st', studio_ip)
    end

    def create_client(tag, name)
      HCKClient.new(@project, self, @studio, tag, name)
    end

    def abort_studio
      @logger.info('Abort is currently not supported for physical machines')
    end

    def abort_client(_name)
      @logger.info('Abort is currently not supported for physical machines')
    end

    def close
      @logger.info('Closing setup manager')
    end
  end
end
