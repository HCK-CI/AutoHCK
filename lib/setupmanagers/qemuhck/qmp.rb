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

      private

      def run_cmd(cmd)
        unless @negotiated
          send_cmd 'qmp_capabilities'
          @negotiated = true
        end

        send_cmd cmd
      end

      def send_cmd(cmd)
        @socket_internal.write JSON.dump({ 'execute' => cmd })
        @socket_internal.flush

        loop do
          response = JSON.parse(@socket_internal.readline)
          break response['return'] if response.key?('return')
          raise response['error'].to_s if response.key?('error')
        end
      end
    end
  end
end
