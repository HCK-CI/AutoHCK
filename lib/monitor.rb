# frozen_string_literal: true

require 'net-telnet'

# monitor class
class Monitor
  MONITOR_BASE_PORT = 10_000
  TIMEOUT = 30
  LOCALHOST = 'localhost'

  def initialize(project, machine)
    @name = machine.name
    @id = machine.id
    @virthck_id = project.virthck.id
    client_id = 3 * @virthck_id.to_i - 2 + @id.to_i
    @port = MONITOR_BASE_PORT + client_id
    @logger = project.logger
    @logger.info('Initiating qemu-monitor session')
  end

  def quit
    @logger.info("Sending quit signal to #{@name} via qemu-monitor")
    cmd('quit')
  end

  def powerdown
    @logger.info("Sending powerdown signal to #{@name} via qemu-monitor")
    cmd('system_powerdown')
  end

  def reset
    @logger.info("Sending reset signal to #{@name} via qemu-monitor")
    cmd('system_reset')
  end

  def cmd(cmd)
    monitor = Net::Telnet.new('Host' => LOCALHOST,
                              'Port' => @port,
                              'Timeout' => TIMEOUT,
                              'Prompt' => /\(qemu\)/)
    monitor.cmd(cmd)
    monitor.close
  rescue Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED
    @logger.warn("#{@name} qemu-monitor not responding")
  end
end
