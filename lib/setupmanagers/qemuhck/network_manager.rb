# frozen_string_literal: true

require_relative '../../auxiliary/json_helper'
require_relative '../../auxiliary/host_helper'
require_relative '../../auxiliary/string_helper'

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # NetworkManager module
    class NetworkManager
      include Helper

      DEVICES_JSON_DIR = 'lib/setupmanagers/qemuhck/devices'
      CONFIG_JSON = 'lib/setupmanagers/qemuhck/network_manager.json'

      def initialize(id, client_id, machine, logger)
        @id = id
        @client_id = client_id
        @machine = machine
        @logger = logger
        @dev_id = 0

        @control_bridge = "br_ctrl_#{id}"
        @test_bridge = "br_test_#{id}"

        @config = read_json(CONFIG_JSON, @logger)
      end

      def read_device(device)
        @logger.info("Loading device: #{device}")
        device_json = "#{DEVICES_JSON_DIR}/#{device}.json"
        unless File.exist?(device_json)
          @logger.fatal("#{device} does not exist")
          raise(InvalidConfigFile, "#{device} does not exist")
        end
        read_json(device_json, @logger)
      end

      def create_bridge(bridge, tx_queue_len = 0)
        run_cmd(["brctl show #{bridge} 1>/dev/null 2>&1 || brctl addbr #{bridge}"])
        run_cmd(["ifconfig #{bridge} up"])
        run_cmd(["ifconfig #{bridge} txqueuelen #{tx_queue_len}"]) if tx_queue_len.positive?
      end

      def remove_bridge(bridge)
        run_cmd_no_fail(["ifconfig #{bridge} down"])
        run_cmd_no_fail(["brctl delbr #{bridge}"])
      end

      def net_addr_cmd(addr)
        addr.nil? ? '' : ",addr=#{addr}"
      end

      def device_replacement_list(type, device_info, device_options, device_config, qemu_replacement_list)
        replacement_list = {
          '@net_if_name@' => device_config['ifname'],
          '@net_up_script@' => "@workspace@/#{type}_ifup_@run_id@.sh",
          '@net_if_mac@' => device_config['mac'],
          '@net_addr@' => net_addr_cmd(device_config['address']),
          '@bus_name@' => device_config['bus_name'],
          '@device_id@' => format('%02x', @dev_id)
        }.merge(device_options)

        qemu_replacement_list.merge(device_info['define_variables'].to_h).merge(replacement_list)
      end

      def device_info(type, device_name, device_options, qemu_replacement_list)
        @dev_id += 1

        device = read_device(device_name)
        type_config = @config['devices'][type]

        replacement_list = device_replacement_list(type, device, device_options, type_config, qemu_replacement_list)
        device_command = replace_string_recursive(device['command_line'].join(' '), replacement_list)

        @logger.debug("Device #{device_name} used as #{type} device")
        @logger.debug("Device command: #{device_command}")

        [device_command, replacement_list]
      end

      def create_net_up_script(replacement_list)
        script_data = @config['scripts']['net_up'].join("\n")

        full_name = replace_string_recursive('@net_up_script@', replacement_list)
        file_content = replace_string_recursive(script_data, replacement_list)
        File.open(full_name, 'w') { |f| f.write(file_content) }
        FileUtils.chmod(0o755, full_name)
      end

      def control_device_command(device_name, qemu_replacement_list = {})
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        create_bridge(@control_bridge)
        cmd, replacement_list = device_info(type, device_name, options, qemu_replacement_list)
        create_net_up_script(replacement_list.merge({ '@bridge_name@' => @control_bridge }))

        cmd
      end

      def world_device_command(device_name, bridge_name, qemu_replacement_list = {})
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, replacement_list = device_info(type, device_name, options, qemu_replacement_list)
        create_net_up_script(replacement_list.merge({ '@bridge_name@' => bridge_name }))

        cmd
      end

      def test_device_command(device_name, qemu_replacement_list = {})
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        create_bridge(@test_bridge)
        cmd, replacement_list = device_info(type, device_name, options, qemu_replacement_list)
        create_net_up_script(replacement_list.merge({ '@bridge_name@' => @test_bridge }))

        cmd
      end

      def transfer_device_command(device_name, transfer_net, share_path, qemu_replacement_list = {})
        type = __method__.to_s.split('_').first

        path = File.absolute_path(share_path)

        netdev_options = ",net=#{transfer_net}.0/24,smb=#{path},smbserver=#{transfer_net}.4,restrict=on"
        network_backend = 'user'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        cmd, = device_info(type, device_name, options, qemu_replacement_list)

        cmd
      end

      def close
        remove_bridge(@control_bridge)
        remove_bridge(@test_bridge)
      end
    end
  end
end
