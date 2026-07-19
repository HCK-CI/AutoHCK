# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Functest
    # A single test case loaded from a JSON file
    class TestCase < T::Struct
      extend T::Sig
      extend Models::JsonHelper

      const :name, String
      const :description, T.nilable(String)
      const :test_system_ref, T.nilable(String)
      const :timeout, T.nilable(Integer)
      const :test_steps, T::Array[Models::CommandInfo]
      const :cleanup, T::Array[Models::CommandInfo], default: []

      # Platform client role-ids (e.g. "c1", "c2") this test case needs booted.
      const :clients, T::Array[String], default: ['c1']
    end
  end
end
