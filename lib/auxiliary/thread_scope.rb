# frozen_string_literal: true

module AutoHCK
  # Simple wrapper for a thread that allows adding a thread to a ResourceScope
  class ThreadScope
    def initialize(thread)
      @thread = thread
    end

    def close
      @thread.kill
      @thread.join
    end
  end
end
