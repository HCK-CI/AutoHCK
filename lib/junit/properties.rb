# frozen_string_literal: true

require_relative 'property'

module AutoHCK
  module JUnit
    class Properties
      def initialize(properties = [])
        @properties = properties
      end

      def add_property(name: nil, value: nil, description: nil)
        @properties.append(Property.new(name: name, value: value, description: description))
      end

      def xml(builder)
        builder.properties do
          @properties.each do |property|
            property.xml(builder)
          end
        end
      end
    end
  end
end
