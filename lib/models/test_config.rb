# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    class Parameter < T::Struct
      extend T::Sig

      const :name, String
      const :value, String
    end

    class TestConfig < T::Struct
      extend T::Sig

      const :tests, T::Array[String]
      const :secure, T.nilable(T::Boolean)
      const :kits, T::Array[String], default: []
      const :parameters, T::Array[Parameter], default: []
      const :skip_retry, T::Boolean, default: false
      const :errata, T.nilable(String), default: nil
      const :pre_test_commands, T::Array[CommandInfo], default: []
      const :post_test_commands, T::Array[CommandInfo], default: []
      const :mid_test_controller, T.nilable(String)
      const :nvram_profile, T.nilable(String)
      const :svvp_only, T::Boolean, default: false
    end
  end
end
