# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Functest
    # Sorbet model for a functest suite requirements block
    class SuiteRequirements < T::Struct
      extend T::Sig

      const :drivers, T::Array[String], default: []
      const :platforms, T::Array[String], default: []
      const :extra_software, T::Array[String], default: []
    end

    # Sorbet model for a functest suite JSON file
    class Suite < T::Struct
      extend T::Sig
      extend Models::JsonHelper

      const :name, String
      const :description, T.nilable(String)
      const :test_system_ref, T.nilable(String)
      const :tests, T::Array[String]
      const :requirements, SuiteRequirements, factory: -> { SuiteRequirements.new }
      const :reject_test_names, T::Array[String], default: []
    end
  end
end
