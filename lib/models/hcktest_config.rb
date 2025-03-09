# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
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
