# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class Session < T::Struct
      extend T::Sig
      extend JsonHelper

      const :test, AutoHCK::CLI::TestOptions
      const :common, T.nilable(AutoHCK::CLI::CommonOptions)
    end
  end
end
