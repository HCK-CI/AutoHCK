# frozen_string_literal: true

require_relative 'properties'
require_relative 'test_case_status'
require_relative 'system_out'
require_relative 'system_err'

module AutoHCK
  module JUnit
    class TestCase
      ATTRIBUTES = %i[name classname time file line start-time end-time].freeze
      CHILD_ELEMENTS = %i[skipped failure error properties system-out system-err].freeze

      def initialize(options = {})
        @data = {}
        @children = []

        ATTRIBUTES.each do |attr_name|
          @data[attr_name] = options[attr_name] unless options[attr_name].nil?
        end

        CHILD_ELEMENTS.each do |element|
          @children.append(options[element]) unless options[element].nil?
        end
      end

      def mark_skipped(message: nil, type: nil, description: nil)
        @children.append(SkippedTestCaseStatus.new(message: message, type: type, description: description))
      end

      def skipped?
        @children.any? { |child| child.is_a?(SkippedTestCaseStatus) }
      end

      def mark_failure(message: nil, type: nil, description: nil)
        @children.append(FailureTestCaseStatus.new(message: message, type: type, description: description))
      end

      def failure?
        @children.any? { |child| child.is_a?(FailureTestCaseStatus) }
      end

      def mark_error(message: nil, type: nil, description: nil)
        @children.append(ErrorTestCaseStatus.new(message: message, type: type, description: description))
      end

      def error?
        @children.any? { |child| child.is_a?(ErrorTestCaseStatus) }
      end

      def add_property(name: nil, value: nil, description: nil)
        properties = @children.find { |child| child.is_a?(Properties) }
        if properties.nil?
          properties = Properties.new
          @children.append(properties)
        end

        properties.add_property(name: name, value: value, description: description)
      end

      def add_system_output(data)
        @children.append(SystemOut.new(data))
      end

      def add_system_error(data)
        @children.append(SystemErr.new(data))
      end

      def time
        @data[:time]
      end

      def xml(builder)
        builder.testcase(@data) do
          @children.each do |child|
            child.xml(builder)
          end
        end
      end
    end
  end
end
