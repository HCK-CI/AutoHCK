# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # SVVPConfig class
    class SVVPConfig < T::Struct
      extend T::Sig
      extend JsonHelper

      const :type, Integer
      const :drivers, T::Array[String]

      const :clients_options, HLKPlatformClientsOptions

      const :select_test_names, T.nilable(T::Array[String])
      const :reject_test_names, T.nilable(T::Array[String])
      const :sequence_test_names, T::Array[String], default: []
      const :attach_devices, T::Array[String], default: []

      const :tests_config, T::Array[TestConfig], default: []
    end
  end
end
