# frozen_string_literal: true

require 'socket'

# AutoHCK module
module AutoHCK
  # Slirp class
  class Slirp
    def initialize(path)
      @path = path
    end

    def run(request)
      UNIXSocket.open @path do
        _1.write JSON.dump(request)
        _1.flush

        response = JSON.parse(_1.read)
        raise response['error'].to_s if response.key?('error')

        response['return']
      end
    end
  end
end
