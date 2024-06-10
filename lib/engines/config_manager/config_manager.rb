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
      @project.append_multilog("#{self.class.tag}.log")
    end

    def self.tag(*)
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
