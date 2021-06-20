# frozen_string_literal: true

require 'net-telnet'

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # Monitor class
    class Monitor
      TIMEOUT = 30
      LOCALHOST = 'localhost'

      def initialize(name, port, logger)
        @name = name
        @port = port
        @logger = logger
        @logger.info("Initiating qemu-monitor session for #{name}")
      end

      def quit
        @logger.info("Sending quit signal to #{@name} via qemu-monitor")
        run_cmd('quit')
      end

      def powerdown
        @logger.info("Sending powerdown signal to #{@name} via qemu-monitor")
        run_cmd('system_powerdown')
      end

      def reset
        @logger.info("Sending reset signal to #{@name} via qemu-monitor")
        run_cmd('system_reset')
      end

      def run_cmd(cmd)
        monitor = Net::Telnet.new('Host' => LOCALHOST,
                                  'Port' => @port,
                                  'Timeout' => TIMEOUT,
                                  'Prompt' => /\(qemu\)/)
        monitor.cmd(cmd)
        monitor.close
        true
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED
        @logger.warn("#{@name} qemu-monitor not responding")
        false
      end
    end
  end
end
