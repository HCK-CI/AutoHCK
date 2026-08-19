# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # QMP class
    class QMP
      attr_reader :socket

      def initialize(scope, name, logger)
        @name = name
        @logger = logger
        @negotiated = false
        @events = []
        @logger.info("Initiating QMP session for #{name}")
        @socket, @socket_internal = UNIXSocket.pair
        scope << @socket
        scope << @socket_internal
      end

      def quit
        @logger.info("Sending quit signal to #{@name} via QMP")
        run_cmd('quit')
      end

      def powerdown
        @logger.info("Sending powerdown signal to #{@name} via QMP")
        run_cmd('system_powerdown')
      end

      def run_cmd(cmd, arguments = nil)
        unless @negotiated
          send_cmd 'qmp_capabilities'
          @negotiated = true
        end

        send_cmd(cmd, arguments)
      end

      # Drain stale matching events from the cache, then block until a
      # fresh event arrives on the QMP socket.
      def wait_for(name, accepted, timeout = 60)
        drain_cached_events(name, accepted)
        wait_for_new_event(name, accepted, timeout)
      end

      private

      def drain_cached_events(name, accepted)
        @events.reject! { |e| accepted.include?(e[name]) }
      end

      def wait_for_new_event(name, accepted, timeout)
        Timeout.timeout(timeout) do
          loop do
            response = JSON.parse(@socket_internal.readline)
            @logger.debug("Received QMP message: #{response}")
            return response if accepted.include?(response[name])

            @events << response if response.key?('event')
            raise(QMPError, response['error'].to_s) if response.key?('error')
          end
        end
      end

      def send_cmd(cmd, arguments = nil)
        cmd_hash = { 'execute' => cmd }
        cmd_hash['arguments'] = arguments if arguments
        @socket_internal.write JSON.dump(cmd_hash)
        @socket_internal.flush

        loop do
          response = JSON.parse(@socket_internal.readline)
          if response.key?('event')
            @events << response
            next
          end
          break response['return'] if response.key?('return')
          raise(QMPError, response['error'].to_s) if response.key?('error')
        end
      end
    end
  end
end
