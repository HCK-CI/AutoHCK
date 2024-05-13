# frozen_string_literal: true

module AutoHCK
  class Pgroup
    attr_reader :pid

    def initialize(scope)
      @pid = spawn('true', pgroup: 0)
      scope << self
    end

    def close
      Process.kill 'TERM', -@pid
      Process.wait @pid
    end
  end
end
