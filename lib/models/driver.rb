# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # Driver class
    class Driver < T::Struct
      extend T::Sig
      extend JsonHelper

      prop :short, T.nilable(String)

      const :name, String
      const :device, String
      const :install_method, DriverInstallMethods
      const :type, Integer
      const :support, T::Boolean

      const :inf, T.nilable(String)
      const :sys, T.nilable(String)
      const :install_cert, T.nilable(T::Boolean)
      const :install_command, T.nilable(String)
      const :s3_state, T.nilable(T::Boolean)
      const :s4_state, T.nilable(T::Boolean)
      const :enlightenments_state, T.nilable(T::Boolean)

      const :post_start_commands, T::Array[CommandInfo], default: []
      const :extra_software, T::Array[String], default: []
      const :reject_test_names, T.nilable(T::Array[String])
      const :select_test_names, T.nilable(T::Array[String])
      const :tests_config, T::Array[TestConfig], default: []
    end
  end
end
