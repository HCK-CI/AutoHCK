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
    end

    # HCKTestConfig class
    class HCKTestConfig < T::Struct
      extend T::Sig
      extend JsonHelper

      const :playlists_path, String
      const :filters_path, String
      const :tests_config, T.nilable(T::Array[TestConfig])
    end
  end
end
