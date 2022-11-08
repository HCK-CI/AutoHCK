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
      UNIXSocket.open @path do |socket|
        socket.write JSON.dump(request)
        socket.flush

        response = JSON.parse(socket.read)
        raise response['error'].to_s if response.key?('error')

        response['return']
      end
    end
  end
end
