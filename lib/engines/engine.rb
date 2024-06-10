# frozen_string_literal: true

require './lib/engines/exceptions'
require './lib/setupmanagers/setupmanager'
require './lib/engines/hcktest/hcktest'
require './lib/engines/hckinstall/hckinstall'
require './lib/engines/config_manager/config_manager'

# AutoHCK module
module AutoHCK
  module Engine
    ENGINES = {
      hcktest: HCKTest,
      hckinstall: HCKInstall,
      config_manager: ConfigManager
    }.freeze

    def self.select(name)
      type = ENGINES[name.downcase.to_sym]
      raise InvalidEngineTypeError, "Unknown type engine #{name}" if type.nil?

      type
    end
  end
end
