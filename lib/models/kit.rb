# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class Kit < T::Struct
      extend T::Sig
      extend JsonHelper

      const :name, String
      const :studio_platform, String
      const :extra_software, T::Array[String], default: []

      const :download_url, T.nilable(String)
      const :sha256, T.nilable(String)
    end
  end
end
