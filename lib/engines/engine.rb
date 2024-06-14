# frozen_string_literal: true

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
