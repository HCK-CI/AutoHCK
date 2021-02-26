# frozen_string_literal: true

require 'uri'

require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/auxiliary/iso_helper'
require './lib/engines/hckinstall/setup_scripts_helper'

# AutoHCK module
module AutoHCK
  # HCKInstall class
  class HCKInstall
    include Helper

    attr_reader :platform

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.install_platform}.log")
      @logger.debug('HCKInstall: initialized')
    end

    def driver
      nil
    end

    def run
      @logger.debug('HCKInstall: run')
    end

    def close
      @logger.debug('HCKInstall: close')
    end
  end
end
