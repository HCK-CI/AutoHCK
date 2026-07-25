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
      const :pre_test_commands, T::Array[Models::CommandInfo], default: []
      const :cycles, Integer, default: 1
      prop :test_steps, T::Array[Models::CommandInfo]
      const :cleanup, T::Array[Models::CommandInfo], default: []

      sig { returns(String) }
      def safe_name
        name.gsub(/[^\w\-.]/, '_').gsub(/(^_|_$)/, '')
      end

      sig { void }
      def add_auto_index
        pre_test_commands.each_with_index do |step, index|
          step.desc = "[Pre-test step #{index + 1}] #{step.desc}"
        end

        test_steps.each_with_index do |step, index|
          step.desc = "[Step #{index + 1}] #{step.desc}"
        end
      end

      sig { void }
      def apply_cycles_to_steps
        return if cycles <= 1

        new_test_steps = []
        cycles.times do |cycle|
          test_steps.each do |step|
            new_step = step.dup
            new_step.desc = "[Cycle #{cycle + 1}] #{step.desc}"
            new_test_steps << new_step
          end
        end

        self.test_steps = new_test_steps
      end
    end
  end
end
