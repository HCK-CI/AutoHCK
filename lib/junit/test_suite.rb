# frozen_string_literal: true

require_relative 'test_case'
require_relative 'properties'
require_relative 'system_out'
require_relative 'system_err'

module AutoHCK
  module JUnit
    class TestSuite
      ATTRIBUTES = %i[name file].freeze
      CHILD_ELEMENTS = %i[properties system-out system-err].freeze

      def initialize(options)
        @data = {}
        @test_cases = []
        @children = []

        ATTRIBUTES.each do |attr_name|
          @data[attr_name] = options[attr_name] unless options[attr_name].nil?
        end

        CHILD_ELEMENTS.each do |element|
          @children.append(options[element]) unless options[element].nil?
        end
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

      def add_test_case(test_case)
        @test_cases.append(test_case)
      end

      def calculate_data
        @data['time'] = @test_cases.flat_map(&:time).sum
        @data['failures'] = @test_cases.count(&:failure?)
        @data['errors'] = @test_cases.count(&:error?)
        @data['skipped'] = @test_cases.count(&:skipped?)
        @data['tests'] = @test_cases.size
      end

      def time
        @data['time']
      end

      def failures
        @data['failures']
      end

      def errors
        @data['errors']
      end

      def skipped
        @data['skipped']
      end

      def tests
        @data['tests']
      end

      def xml(builder)
        calculate_data

        builder.testsuite(@data) do
          @test_cases.each do |test_case|
            test_case.xml(builder)
          end
          @children.each do |child|
            child.xml(builder)
          end
        end
      end
    end
  end
end
