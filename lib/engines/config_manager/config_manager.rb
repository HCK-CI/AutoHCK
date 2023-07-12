# frozen_string_literal: true

require 'fileutils'
require './lib/auxiliary/resource_scope'
require './lib/resultuploaders/result_uploader'

# AutoHCK module
module AutoHCK
  # ConfigManager class
  class ConfigManager
    include Helper

    ENGINE_MODE = 'helper'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{tag}.log")
      init_workspace
    end

    def init_workspace
      @workspace_path = [@project.workspace_path,
                         tag, @project.timestamp].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @project.logger.warn('Workspace path already exists')
      end
      @project.move_workspace_to(@workspace_path.to_s)
    end

    def tag
      'helper-config-manager'
    end

    def run
      ResourceScope.open do |scope|
        @project.logger.info('Stating result uploader token initialization')
        @result_uploader = ResultUploader.new(scope, @project)
        @result_uploader.ask_token
      end
    end

    def drivers
      nil
    end

    def platform
      nil
    end

    def result_uploader_needed?
      false
    end
  end
end
