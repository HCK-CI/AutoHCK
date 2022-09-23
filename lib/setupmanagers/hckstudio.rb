# frozen_string_literal: true

require './lib/engines/hcktest/tools'

# AutoHCK module
module AutoHCK
  # HCKStudio class
  class HCKStudio
    attr_reader :tools

    STUDIO = 'st'
    CONNECT_RETRIES = 5
    CONNECT_RETRY_SLEEP = 10

    def initialize(project, setup_manager, &ip_getter)
      @project = project
      @tag = project.engine.tag
      @setup_manager = setup_manager
      @ip_getter = ip_getter
      @logger = project.logger
    end

    def up?
      !@ip_getter.call.nil?
    end

    def create_pool
      @logger.info('Creating pool')
      @tools.create_pool(@tag)
    end

    def delete_pool
      @logger.info('Deleting pool')
      @tools.delete_pool(@tag)
    end

    def create_project
      @logger.info('Creating project')
      @tools.create_project(@tag)
    end

    def delete_project
      @logger.info('Deleting project')
      @tools.delete_project(@tag)
    end

    def list_pools
      @tools.list_pools
    end

    def update_filters
      filters_path = @project.engine.config['filters_path']

      return unless File.file?(filters_path)

      @logger.info('Updating HCK filters')
      @tools.update_filters(filters_path)
    end

    def connect
      retries ||= 0
      begin
        @logger.info('Initiating connection to studio')
        @tools = Tools.new(@project, @ip_getter.call, @clients)
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, RToolsHCKConnectionError
        raise StudioConnectError, 'Initiating connection to studio failed'
      end
    rescue StudioConnectError => e
      @logger.warn(e.message)
      raise unless (retries + 1) < CONNECT_RETRIES

      sleep CONNECT_RETRY_SLEEP
      @logger.info('Trying again to initiate connection to studio')
      retry
    end

    def verify_tools
      return if @tools.connection_check

      raise StudioConnectError, 'Tools did not pass the connection check'
    end

    def run(run_opts = nil)
      @setup_manager.run(STUDIO, run_opts)
    end

    def alive?
      @setup_manager.studio_alive?
    end

    def clean_tools
      delete_project
      delete_pool
      @tools&.close
      @tools = nil
    end

    def clean_last_run
      clean_tools unless @tools.nil?
      @setup_manager.clean_last_studio_run
    end

    def configure(clients)
      @clients = clients
      @logger.info('Waiting for studio to load...')
      sleep 5 until up?
      connect
      verify_tools
      update_filters
      create_pool
      create_project
    end

    def abort
      @logger.info('Aborting HLK Studio')
      @tools&.close unless @tools.nil?
      @setup_manager.abort_studio
    end

    def shutdown
      @logger.info('Shutting down studio')
      @tools.shutdown
    end
  end
end
