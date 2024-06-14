# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  module SetupManager
    SETUP_MANAGERS = {
      qemuhck: QemuHCK,
      physhck: PhysHCK
    }.freeze

    def self.select(name)
      type = SETUP_MANAGERS[name.downcase.to_sym]
      raise SetupManagerError, "Unknown type setup manager #{name}" if type.nil?

      type
    end
  end
end
