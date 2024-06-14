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
      const :pluggable_memory_gb, T.nilable(Integer)

      const :pretestcommands, T.nilable(T::Array[CommandInfo])
      const :extra_software, T.nilable(T::Array[String])
      const :reject_test_names, T.nilable(T::Array[String])
      const :select_test_names, T.nilable(T::Array[String])
    end
  end
end
