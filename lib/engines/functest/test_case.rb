# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Functest
    # Config for a qmp_command step
    class QmpCommandConfig < T::Struct
      extend T::Sig

      const :execute, String
      const :arguments, T.nilable(T::Hash[String, T.untyped])
    end

    # Config for a qmp_wait_event step
    class QmpWaitEventConfig < T::Struct
      extend T::Sig

      const :event, String
      const :timeout, T.nilable(Integer)
    end

    # A single test step. Exactly one step-type field should be set; the rest must stay nil.
    #
    # Fields shared with AutoHCK::Models::CommandInfo (hcktest):
    #   desc, guest_run, guest_reboot, files_action, host_run
    #
    # Functest-only fields (not processed by hcktest):
    #   timeout, capture_output, ignore_errors, variables,
    #   guest_run_file, barrier, qmp_command, qmp_wait_event,
    #   expected_output_contains, expected_output_matches
    class TestStep < T::Struct
      extend T::Sig

      # Common fields
      const :desc, T.nilable(String)
      const :timeout, T.nilable(Integer)
      const :capture_output, T.nilable(String)
      const :ignore_errors, T.nilable(T::Boolean)
      const :variables, T::Hash[String, String], default: {}

      # Step type fields — exactly one should be non-nil/truthy
      const :guest_run, T.nilable(String)
      const :guest_run_file, T.nilable(String)
      const :guest_reboot, T.nilable(T::Boolean)
      const :files_action, T.nilable(T::Array[Models::FileActionConfig])
      const :host_run, T.nilable(String)
      const :barrier, T.nilable(String)
      const :qmp_command, T.nilable(QmpCommandConfig)
      const :qmp_wait_event, T.nilable(QmpWaitEventConfig)

      # Output validation
      const :expected_output_contains, T.nilable(String)
      const :expected_output_matches, T.nilable(String)
    end

    # A single test case loaded from a JSON file
    class TestCase < T::Struct
      extend T::Sig
      extend Models::JsonHelper

      const :name, String
      const :description, T.nilable(String)
      const :test_system_ref, T.nilable(String)
      const :timeout, T.nilable(Integer)
      const :test_steps, T::Array[TestStep]
      const :cleanup, T::Array[TestStep], default: []
    end
  end
end
