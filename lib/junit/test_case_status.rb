# frozen_string_literal: true

module AutoHCK
  module JUnit
    class TestCaseStatus
      def initialize(message: nil, type: nil, description: nil)
        @data = {}
        @data[:message] = message unless message.nil?
        @data[:type] = type unless type.nil?

        @description = description
      end
    end

    class SkippedTestCaseStatus < TestCaseStatus
      def xml(builder)
        builder.skipped(@data) do
          builder.text @description
        end
      end
    end

    class FailureTestCaseStatus < TestCaseStatus
      def xml(builder)
        builder.failure(@data) do
          builder.text @description
        end
      end
    end

    class ErrorTestCaseStatus < TestCaseStatus
      def xml(builder)
        builder.error(@data) do
          builder.text @description
        end
      end
    end
  end
end
