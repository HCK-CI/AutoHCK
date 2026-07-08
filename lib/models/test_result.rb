# frozen_string_literal: true

module AutoHCK
  module Models
    # A single test result used by JUnit, HTML report, and project status.
    # Both engines produce this via from_hlk_test or from_functest.
    class TestResult < T::Struct
      extend T::Sig
      include Helper
      extend Helper
      include HLK::TestResultStatusPredicates

      const :name,             String
      const :status,           HLK::TestResultStatus, override: true
      const :executionstate,   HLK::ExecutionState
      const :execution_time,   Float
      const :is_skipped,       T::Boolean
      const :errata,           T.nilable(String)
      const :last_result,      T.untyped, default: nil
      const :dump_path,        T.nilable(String)
      const :url,              T.nilable(String)
      const :estimatedruntime, String

      def self.from_hlk_test(test)
        new(
          name: test.name,
          status: test.status,
          executionstate: test.executionstate,
          execution_time: test.execution_time.to_f,
          is_skipped: test.is_skipped,
          errata: test.errata,
          last_result: test.last_result,
          dump_path: test.dump_path,
          url: test.url,
          estimatedruntime: test.estimatedruntime
        )
      end

      def self.from_functest(result_hash)
        new(
          name: result_hash[:name],
          status: case result_hash[:status]
                  when 'passed' then HLK::TestResultStatus::Passed
                  when 'failed' then HLK::TestResultStatus::Failed
                  else raise "Unexpected functest status: #{result_hash[:status]}"
                  end,
          executionstate: HLK::ExecutionState::NotRunning,
          execution_time: result_hash[:duration].to_f,
          is_skipped: false,
          errata: nil,
          last_result: result_hash,
          dump_path: result_hash[:dump_path],
          url: nil,
          estimatedruntime: seconds_to_time(result_hash[:duration].to_i)
        )
      end
    end
  end
end
