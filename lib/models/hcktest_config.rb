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
    end
  end
end
