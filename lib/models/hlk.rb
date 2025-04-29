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

        sig { returns(Float) }
        def duration
          time_to_seconds(estimatedruntime)
        end
      end
    end
  end
end
