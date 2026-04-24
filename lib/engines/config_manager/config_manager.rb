# frozen_string_literal: true

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
      @project.notification_manager.post_engine_init(self)
    end

    def self.tag(*)
      'helper-config-manager'
    end

    def test_steps
      []
    end

    def run
      @project.notification_manager.pre_engine_run(self)
      ResourceScope.open do |scope|
        @project.logger.info('Stating result uploader token initialization')
        @result_uploader = ResultUploader.new(scope, @project)
        @result_uploader.ask_token
      end
    ensure
      @project.notification_manager.post_engine_run(self)
    end

    def drivers
      nil
    end

    def self.platform(*)
      nil
    end

    def result_uploader_needed?
      false
    end

    def target
      nil
    end
  end
end
