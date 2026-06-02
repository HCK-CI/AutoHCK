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
    end
  end
end
