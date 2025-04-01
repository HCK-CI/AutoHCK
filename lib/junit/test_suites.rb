# frozen_string_literal: true

require_relative 'test_suite'

module AutoHCK
  module JUnit
    class TestSuites
      ATTRIBUTES = %i[name].freeze

      def initialize(options)
        @data = {}
        @test_suites = []

        ATTRIBUTES.each do |attr_name|
          @data[attr_name] = options[attr_name] unless options[attr_name].nil?
        end
      end

      def add_test_suite(test_suite)
        @test_suites.append(test_suite)
      end

      def calculate_data
        @test_suites.each(&:calculate_data)

        %w[time failures errors skipped tests].each do |key|
          @data[key] = @test_suites.flat_map(&key.to_sym.to_proc).sum
        end
      end

      def xml(builder)
        calculate_data

        builder.testsuites(@data) do
          @test_suites.each do |test_suite|
            test_suite.xml(builder)
          end
        end
      end
    end
  end
end
