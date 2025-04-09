# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    class ClientPlatformOptions < T::Struct
      extend T::Sig
      extend JsonHelper

      const :viommu_state, T::Boolean, default: false
      const :enlightenments_state, T::Boolean, default: false
      const :ctrl_net_device, String, default: 'e1000e'
    end

    # SVVPConfig class
    class SVVPConfig < T::Struct
      extend T::Sig
      extend JsonHelper

      const :type, Integer
      const :drivers, T::Array[String]

      const :clients_options, ClientPlatformOptions

      const :select_test_names, T.nilable(T::Array[String])
      const :reject_test_names, T.nilable(T::Array[String])
    end
  end
end
