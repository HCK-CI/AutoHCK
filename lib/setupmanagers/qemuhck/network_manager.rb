# frozen_string_literal: true

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
        Models::QemuHCKDevice.from_json_file("#{DEVICES_JSON_DIR}/#{device}.json", @logger)
      end

      def find_world_ip(*)
        UDPSocket.open do |socket|
          (15..30).map { socket.send('', 0, "10.0.2.#{_1}", 9) }
        end

        read_world_ip(*)
      end

      def read_world_ip(device_name, qemu_replacement_map)
        device = read_device(device_name)
        type_config = @config['devices']['world']
        replacement_map = device_replacement_map('world', device, type_config, {}, qemu_replacement_map)
        mac = replacement_map.replace(type_config['mac'])

        found = File.readlines('/proc/net/arp')[1..].map(&:split).find do |candidate|
          candidate[3] == mac && candidate[5] == 'br_world'
        end

        found&.first
      end

      def net_addr_cmd(addr)
        addr.nil? ? '' : ",addr=#{addr}"
      end

      def device_replacement_map(type, device_info, device_config, dev_pci, qemu_replacement_map)
        replacement_map = {
          '@net_if_name@' => device_config['ifname'],
          '@net_up_script@' => "@workspace@/#{type}_ifup_@run_id@.sh",
          '@net_if_mac@' => device_config['mac'],
          '@net_addr@' => net_addr_cmd(dev_pci.fetch('address', nil)),
          '@bus_name@' => dev_pci['bus_name'],
          '@device_id@' => format('%02x', @dev_id)
        }

        qemu_replacement_map.merge(replacement_map, device_info.define_variables)
      end

      def device_command_info(type, device, command_options, dev_pci, qemu_replacement_map)
        @dev_id += 1

        type_config = @config['devices'][type]

        replacement_map = device_replacement_map(type, device, type_config, dev_pci, qemu_replacement_map)
        replacement_map.merge! command_options
        device_command = replacement_map.create_cmd(device.command_line.join(' '))

        @logger.debug("Device #{device.name} used as #{type} device")
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

      def create_net_smb(replacement_map)
        content = replacement_map.replace(@config['smb'].join("\n"))
        path = replacement_map.replace('@workspace@/@net_smb_private@')

        begin
          Dir.mkdir path
        rescue Errno::EEXIST
          # An earlier run created the directory.
        end

        File.write File.join(path, 'smb.conf'), content
      end

      def control_device_command(device, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no,ifname=@net_if_name@'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        # Don't redefine the bus name, it should be predefined to prevent
        # Windows device reinstallation.
        dev_pci = {
          'bus_name' => @machine['ctrl_dev_bus_name'],
          'address' => @machine['ctrl_dev_address']
        }
        cmd, replacement_map = device_command_info(type, device, options, dev_pci, qemu_replacement_map)
        create_net_up_script(replacement_map.merge({ '@bridge_name@' => 'br_ctrl' }))

        cmd
      end

      def world_device_command(device, bus_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first
        create_tap_device_command(type, device, bus_name, 'br_world', qemu_replacement_map)
      end

      def test_device_command(device, bus_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first
        create_tap_device_command(type, device, bus_name, 'br_test', qemu_replacement_map)
      end

      def debug_device_command(device, bus_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first
        create_tap_device_command(type, device, bus_name, 'br_debug', qemu_replacement_map)
      end

      def transfer_device_command(device, transfer_net, share_path, bus_name, qemu_replacement_map)
        type = __method__.to_s.split('_').first

        path = File.absolute_path(share_path)

        net_base = "#{transfer_net}.0/24"
        smb_server = "#{transfer_net}.4"

        # Mapping the current user to root will make smbd assume it can drop and
        # re-add supplementary groups. However, re-adding supplementary groups
        # do not work because they are typically not mapped in the current user
        # namespace. Map the current user to nobody when running smbd so that
        # smbd will run in the non-root mode.
        net_smb_cmd = qemu_replacement_map.create_cmd(
          'unshare --map-user=nobody smbd -l smb_@run_id@_@client_id@ -s smb_@run_id@_@client_id@/smb.conf'
        )

        netdev_options = ",net=#{net_base},guestfwd=:#{smb_server}:445-cmd:#{net_smb_cmd},restrict=on"
        network_backend = 'user'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options,
          '@net_smb_private@' => 'smb_@run_id@_@client_id@',
          '@net_smb_share@' => path
        }

        dev_pci = { 'bus_name' => bus_name }
        cmd, replacement_map = device_command_info(type, device, options, dev_pci, qemu_replacement_map)
        create_net_smb replacement_map

        cmd
      end

      private

      def create_tap_device_command(type, device, bus_name, bridge_name, qemu_replacement_map)
        netdev_options = ',vhost=@vhost_value@,script=@net_up_script@,downscript=no,ifname=@net_if_name@'
        network_backend = 'tap'

        options = {
          '@network_backend@' => network_backend,
          '@netdev_options@' => netdev_options
        }

        dev_pci = { 'bus_name' => bus_name }
        cmd, replacement_map = device_command_info(type, device, options, dev_pci, qemu_replacement_map)
        create_net_up_script(replacement_map.merge({ '@bridge_name@' => bridge_name }))

        cmd
      end
    end
  end
end
