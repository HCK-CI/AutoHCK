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
      const :parameters, T::Array[Parameter], default: []
      const :pre_test_commands, T::Array[CommandInfo], default: []
      const :post_test_commands, T::Array[CommandInfo], default: []
    end
  end
end
