# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # SVVPConfig class
    class SVVPConfig < T::Struct
      extend T::Sig
      extend JsonHelper

      const :type, Integer
      const :drivers, T::Array[String]

      const :select_test_names, T.nilable(T::Array[String])
      const :reject_test_names, T.nilable(T::Array[String])
    end
  end
end
