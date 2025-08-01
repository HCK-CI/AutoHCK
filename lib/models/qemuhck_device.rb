# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class QemuHCKDevice < T::Struct
      extend T::Sig
      extend JsonHelper

      const :name, String
      const :type, T.nilable(String)
      const :command_line, T::Array[String]
      const :define_variables, T::Hash[String, String], default: {}
      const :config_commands, T::Array[String], default: []
      const :pre_start_commands, T::Array[String], default: []
      const :post_stop_commands, T::Array[String], default: []
      const :machine_options, T::Array[String], default: []
      const :need_pci_bus, T::Boolean, default: false
      const :pluggable_memory_gb, Integer, default: 0
      const :iommu_device_param, T.nilable(String)
    end
  end
end
