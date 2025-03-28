# frozen_string_literal: true

module AutoHCK
  module JUnit
    class Property
      def initialize(name: nil, value: nil, description: nil)
        @name = name
        @value = value
        @description = description
      end

      def xml(builder)
        builder.property(name: @name, value: @value) do
          builder.text @description
        end
      end
    end
  end
end
