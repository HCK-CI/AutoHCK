# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Functest
    # Declares a known-issue test case failure for a functest suite. Test
    # cases matching `tests` (by name regex) and `platforms` (current run
    # platform, empty matches all) are reported as "passed with errata"
    # instead of a genuine failure when they fail.
    class KnownIssue < T::Struct
      extend T::Sig

      const :tests, T::Array[String]
      const :platforms, T::Array[String], default: []
      const :reason, String
    end
  end
end
