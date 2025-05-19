# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    module HLK
      class ExecutionState < T::Enum
        extend T::Sig

        enums do
          InQueue = new('InQueue')
          NotRunning = new('NotRunning')
          Running = new('Running')
        end

        sig { returns(String) }
        def to_s
          serialize
        end
      end

      class TestResultStatus < T::Enum
        extend T::Sig

        enums do
          Canceled = new('Canceled')
          Failed = new('Failed')
          InQueue = new('InQueue')
          NotRun = new('NotRun')
          Passed = new('Passed')
          Running = new('Running')
        end

        sig { returns(String) }
        def to_s
          serialize
        end
      end

      class TestType < T::Enum
        extend T::Sig

        enums do
          Automated = new('Automated')
          Configuration = new('Configuration')
          Library = new('Library')
          Manual = new('Manual')
        end

        sig { returns(String) }
        def to_s
          serialize
        end
      end

      class Test < T::Struct
        extend T::Sig
        extend JsonHelper
        include Helper

        const :name, String
        const :id, String
        const :testtype, TestType
        const :estimatedruntime, String
        const :requiresspecialconfiguration, String
        const :requiressupplementalcontent, String
        const :scheduleoptions, T::Array[String]
        const :status, TestResultStatus
        const :executionstate, ExecutionState

        prop :url, T.nilable(String)
        prop :run_count, Integer, default: 1

        sig { returns(String) }
        def safe_name
          name.gsub(/[^\w\-\.]/, '_').gsub(/(^_|_$)/, '')
        end

        # Extra information
        prop :ex_status, T.nilable(String)
        prop :queued_at, T.nilable(DateTime)
        prop :started_at, T.nilable(DateTime)
        prop :finished_at, T.nilable(DateTime)
        prop :dump_path, T.nilable(String)
        prop :last_result, T.nilable(T::Hash[String, T.untyped])
        prop :is_skipped, T::Boolean, default: false

        sig { params(hck_test: Test).void }
        def update_from_hck(hck_test)
          @name = hck_test.name
          @id = hck_test.id
          @testtype = hck_test.testtype
          @estimatedruntime = hck_test.estimatedruntime
          @requiresspecialconfiguration = hck_test.requiresspecialconfiguration
          @requiressupplementalcontent = hck_test.requiressupplementalcontent
          @scheduleoptions = hck_test.scheduleoptions
          @status = hck_test.status
          @executionstate = hck_test.executionstate
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def extra
          {
            'ex_status' => ex_status,
            'queued_at' => queued_at,
            'started_at' => started_at,
            'finished_at' => finished_at,
            'dump_path' => dump_path
          }
        end

        sig { returns(Integer) }
        def execution_time
          return 0 if finished_at.nil?

          if started_at.nil?
            return 0 if queued_at.nil?

            return time_diff(queued_at, finished_at)
          end

          time_diff(started_at, finished_at)
        end

        sig { returns(Float) }
        def duration
          time_to_seconds(estimatedruntime)
        end
      end
    end
  end
end
