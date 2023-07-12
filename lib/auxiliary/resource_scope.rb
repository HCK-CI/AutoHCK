# frozen_string_literal: true

require './lib/exceptions'

module AutoHCK
  # ResourceScope is a class that manages objects with close methods.
  class ResourceScope
    def initialize(resources)
      @resources = resources
    end

    def <<(resource)
      @resources << resource
      self
    end

    def transaction
      resources = []
      self.class.open(resources) do |scope|
        result = yield(scope)
        @resources.concat resources
        resources.clear
        result
      end
    end

    def self.open(resources = [])
      scope = new(resources)
      Thread.handle_interrupt(AutoHCKInterrupt => :never) do
        Thread.handle_interrupt(AutoHCKInterrupt => :on_blocking) do
          yield scope
        end
      ensure
        resources.reverse_each(&:close)
      end
    end
  end
end
