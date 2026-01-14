# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class Extension < T::Struct
      extend T::Sig
      extend JsonHelper

      prop :short, T.nilable(String)

      const :extra_software, T::Array[String], default: []
      const :post_start_commands, T::Array[CommandInfo], default: []
      const :tests_config, T::Array[TestConfig], default: []
    end
  end
end
