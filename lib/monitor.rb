require 'net-telnet'

# monitor class
class Monitor
  MONITOR_BASE_PORT = 10_000
  TIMEOUT = 30
  LOCALHOST = 'localhost'.freeze

  def initialize(project, machine)
    @name = machine.name
    @id = machine.id
    @virthck_id = project.virthck.id
    client_id = 3 * @virthck_id.to_i - 2 + @id.to_i
    @port = MONITOR_BASE_PORT + client_id
    @logger = project.logger
    @logger.info('Initiating qemu-monitor session')
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
  rescue Net::ReadTimeout, Errno::ECONNRESET
    @logger.error('Monitor not responding')
  end
end
