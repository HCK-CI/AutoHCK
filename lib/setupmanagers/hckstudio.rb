# frozen_string_literal: true

require 'net/ping'
require './lib/setupmanagers/machine'
require './lib/engines/hcktest/tools'

# AutoHCK module
module AutoHCK
  # HCKStudio class
  class HCKStudio < Machine
    attr_reader :tools, :name, :id, :setupmanager
    HCK_FILTERS_PATH = 'filters/UpdateFilters.sql'
    def initialize(project, setupmanager, name, ip)
      super(project, name, setupmanager, 0, 'st')
      @ip = ip
    end

    def up?
      check = Net::Ping::External.new(@ip)
      check.ping?
    end

    def create_snapshot
      @setupmanager.create_studio_snapshot
    end

    def delete_snapshot
      @setupmanager.delete_studio_snapshot
    end

    def create_pool
      @logger.info('Creating pool')
      tag = @project.tag
      @tools.create_pool(tag)
    end

    def delete_pool
      @logger.info('Deleting pool')
      tag = @project.tag
      @tools.delete_pool(tag)
    end

    def create_project
      @logger.info('Creating project')
      tag = @project.tag
      @tools.create_project(tag)
    end

    def delete_project
      @logger.info('Deleting project')
      tag = @project.tag
      @tools.delete_project(tag)
    end

    def list_pools
      @tools.list_pools
    end

    def update_filters
      return unless File.file?(HCK_FILTERS_PATH)

      @logger.info('Updating HCK filters')
      @tools.update_filters(HCK_FILTERS_PATH)
    end

    CONNECT_RETRIES = 5
    CONNECT_RETRY_SLEEP = 10

    def connect
      retries ||= 0
      begin
        @logger.info('Initiating connection to studio')
        @tools = Tools.new(@project, @ip, @clients)
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

    def run
      create_snapshot
      super
    end

    def clean_tools
      delete_project
      delete_pool
      @tools&.close
      @tools = nil
    end

    def clean_last_run
      clean_tools unless @tools.nil?
      super
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
      @tools&.close unless @tools.nil?
      super
    end

    def shutdown
      @logger.info('Shutting down studio')
      @tools.shutdown
    end
  end
end
