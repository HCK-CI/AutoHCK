# frozen_string_literal: true

module AutoHCK
  module Functest
    # A TestContext for one parallel branch. Reads see a snapshot of the
    # parent's variables; writes are buffered in #pending_captures instead
    # of the parent's shared state, so concurrent branches never race.
    class BranchContext < TestContext
      attr_reader :pending_captures

      def initialize(parent_context)
        super(parent_context.project, parent_context.replacement_map)
        @pending_captures = {}
      end

      # Used by capture_output, the only way a branch writes a variable.
      def set_variable(name, value)
        super
        @pending_captures[name] = value.to_s
      end
    end
  end
end
