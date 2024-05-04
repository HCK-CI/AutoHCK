# frozen_string_literal: true

require_relative '../../auxiliary/json_helper'
require_relative '../../auxiliary/host_helper'
require_relative '../../auxiliary/replacement_map'

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # NetworkManager module
    class NetworkManager
      include Helper

      CONFIG_JSON = 'lib/setupmanagers/qemuhck/network_manager.json'

      def initialize(id, client_id, machine, logger)
        @id = id
        @client_id = client_id
        @machine = machine
        @logger = logger
        @dev_id = 0

        @config = Json.read_json(CONFIG_JSON, @logger)
      end

      def read_device(device)
        @logger.info("Loading device: #{device}")
        device_json = "#{DEVICES_JSON_DIR}/#{device}.json"
        unless File.exist?(device_json)
          @logger.fatal("#{device} does not exist")
          raise(InvalidConfigFile, "#{device} does not exist")
        end
        Json.read_json(device_json, @logger)
      end

      def find_world_ip(*args)
        UDPSocket.open do |socket|
          (15..30).map { socket.send('', 0, "10.0.2.#{_1}", 9) }
        end

        read_world_ip(*args)
      end

      def read_world_ip(device_name, qemu_replacement_map)
        device = read_device(device_name)
        type_config = @config['devices']['world']
        replacement_map = device_replacement_map('world', device, type_config, qemu_replacement_map)
        mac = replacement_map.replace(type_config['mac'])

        found = File.readlines('/proc/net/arp')[1..].map(&:split).find do |candidate|
          candidate[3] == mac && candidate[5] == 'br_world'
        end

        found&.first
      end

      def net_addr_cmd(addr)
        addr.nil? ? '' : ",addr=#{addr}"
      end

      def device_replacement_map(type, device_info, device_config, qemu_replacement_map)
        replacement_map = {
          '@net_if_name@' => device_config['ifname'],
          '@net_up_script@' => "@workspace@/#{type}_ifup_@run_id@.sh",
          '@net_if_mac@' => device_config['mac'],
          '@net_addr@' => net_addr_cmd(device_config['address']),
          '@bus_name@' => device_config['bus_name'],
          '@device_id@' => format('%02x', @dev_id)
        }

        qemu_replacement_map.merge(replacement_map, device_info['define_variables'])
      end

      def device_command_info(type, device_name, command_options, qemu_replacement_map)
        @dev_id += 1

        device = read_device(device_name)
        type_config = @config['devices'][type]

        replacement_map = device_replacement_map(type, device, type_config, qemu_replacement_map)
        replacement_map.merge! command_options
        device_command = replacement_map.create_cmd(device['command_line'].join(' '))

        @logger.debug("Device #{device_name} used as #{type} device")
        @logger.debug("Device command: #{device_command}")

        [device_command, replacement_map]
      end

      def create_net_up_script(replacement_map)
        script_data = @config['scripts']['net_up'].join("\n")

        full_name = replacement_map.replace('@net_up_script@')
        file_content = replacement_map.create_cmd(script_data)
        File.write(full_name, file_content)
        FileUtils.chmod(0o755, full_name)
      end

      def control_device_command(device_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no,ifname=@net_if_name@'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, replacement_map = device_command_info(type, device_name, options, qemu_replacement_map)
        create_net_up_script(replacement_map.merge({ '@bridge_name@' => 'br_ctrl' }))

        cmd
      end

      def world_device_command(device_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no,ifname=@net_if_name@'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, replacement_map = device_command_info(type, device_name, options, qemu_replacement_map)
        create_net_up_script(replacement_map.merge({ '@bridge_name@' => 'br_world' }))

        cmd
      end

      def test_device_command(device_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no,ifname=@net_if_name@'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, replacement_map = device_command_info(type, device_name, options, qemu_replacement_map)
        create_net_up_script(replacement_map.merge({ '@bridge_name@' => 'br_test' }))

        cmd
      end

      def transfer_device_command(device_name, transfer_net, share_path, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        path = File.absolute_path(share_path)

        net_base = "#{transfer_net}.0/24"
        smb_server = "#{transfer_net}.4"

        netdev_options = "net=#{net_base},smb=#{path},smbserver=#{smb_server},restrict=on,ifname=@net_if_name@"
        network_backend = 'user'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, = device_command_info(type, device_name, options, qemu_replacement_map)

        cmd
      end
    end
  end
end
