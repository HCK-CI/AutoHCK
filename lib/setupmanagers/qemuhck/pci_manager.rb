# typed: true
# frozen_string_literal: true

module AutoHCK
  class QemuMachine
    class PciManager
      extend T::Sig
      include Helper

      DEVICES_JSON_DIR = 'lib/setupmanagers/qemuhck/devices'

      def initialize(logger)
        @logger = logger
        @dev_id = 0

        # First free PCI slot, chassis and address
        @pci_slot = 4
        @pci_chassis = 2
        @pci_addr = 5
      end

      sig { params(device: String).returns(Models::QemuHCKDevice) }
      def read_device(device)
        @logger.info("Loading device: #{device}")
        Models::QemuHCKDevice.from_json_file("#{DEVICES_JSON_DIR}/#{device}.json", @logger)
      end

      def next_pci_device
        @pci_slot += 1
        @pci_chassis += 1
        @pci_addr += 1
      end

      def create_pci_root_port
        @logger.info("Creating PCI root port with slot #{@pci_slot}, chassis #{@pci_chassis}, address #{@pci_addr}")

        device_info = read_device('pcie-root-port')
        pci_replacement_map = ReplacementMap.new(
          '@pci_root_slot@' => @pci_slot,
          '@pci_root_chassis@' => @pci_chassis,
          '@pci_root_addr@' => format('0x%02x', @pci_addr),
          **device_info.define_variables
        )

        dirty_cmd = device_info.command_line.join(' ')
        cmd = pci_replacement_map.create_cmd(dirty_cmd)

        @logger.debug("PCI root port command: #{cmd}")

        next_pci_device

        [cmd, pci_replacement_map['@bus_name@']]
      end
    end
  end
end
