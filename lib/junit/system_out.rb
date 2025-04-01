# frozen_string_literal: true

module AutoHCK
  module JUnit
    class SystemOut
      def initialize(data)
        @data = data
      end

      def xml(builder)
        builder.send(:'system-out') do
          builder.text @data
        end
      end
    end
  end
end
