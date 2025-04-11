# frozen_string_literal: true

module AutoHCK
  module JUnit
    class SystemErr
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
