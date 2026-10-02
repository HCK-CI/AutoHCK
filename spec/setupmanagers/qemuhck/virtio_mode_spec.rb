# frozen_string_literal: true

require_relative '../../../lib/all'
require_relative '../../../lib/setupmanagers/qemuhck/virtio_mode'

describe AutoHCK::QemuMachine::VirtioMode do
  # --- validate! ---
  describe '.validate!' do
    it 'accepts valid modes' do
      %w[modern legacy transitional].each do |mode|
        expect { described_class.validate!(mode) }.not_to raise_error
      end
    end

    it 'accepts nil and empty string' do
      expect { described_class.validate!(nil) }.not_to raise_error
      expect { described_class.validate!('') }.not_to raise_error
    end

    it 'rejects invalid mode' do
      expect { described_class.validate!('turbo') }
        .to raise_error(AutoHCK::AutoHCKError, /Invalid virtio mode/)
    end
  end

  # --- qemu_device_suffix ---
  describe '.qemu_device_suffix' do
    it 'returns modern suffix' do
      expect(described_class.qemu_device_suffix('modern'))
        .to eq(',disable-legacy=on,disable-modern=off')
    end

    it 'returns legacy suffix' do
      expect(described_class.qemu_device_suffix('legacy'))
        .to eq(',disable-legacy=off,disable-modern=on')
    end

    it 'returns transitional suffix' do
      expect(described_class.qemu_device_suffix('transitional'))
        .to eq(',disable-legacy=off,disable-modern=off')
    end

    it 'returns empty string for nil' do
      expect(described_class.qemu_device_suffix(nil)).to eq('')
    end

    it 'returns empty string for empty string' do
      expect(described_class.qemu_device_suffix('')).to eq('')
    end
  end

  # --- validate_devices_for_mode! ---
  describe '.validate_devices_for_mode!' do
    it 'passes for supported devices' do
      expect { described_class.validate_devices_for_mode!('modern', ['virtio-net-pci']) }
        .not_to raise_error
    end

    it 'passes for multiple supported devices' do
      expect { described_class.validate_devices_for_mode!('legacy', %w[virtio-net-pci virtio-blk-pci]) }
        .not_to raise_error
    end

    it 'skips validation when mode is nil' do
      expect { described_class.validate_devices_for_mode!(nil, []) }
        .not_to raise_error
    end

    it 'raises when device list is empty' do
      expect { described_class.validate_devices_for_mode!('modern', []) }
        .to raise_error(AutoHCK::AutoHCKError, /requires -d/)
    end

    it 'raises for unsupported device' do
      expect { described_class.validate_devices_for_mode!('modern', ['fwcfg64']) }
        .to raise_error(AutoHCK::AutoHCKError, /not supported/)
    end
  end

  # --- validate_qtree! ---
  describe '.validate_qtree!' do
    let(:modern_qtree) do
      <<~QTREE
        dev: virtio-net-pci, id=net0
          disable-legacy = "on"
          disable-modern = "off"
      QTREE
    end

    let(:legacy_qtree) do
      <<~QTREE
        dev: virtio-net-pci, id=net0
          disable-legacy = "off"
          disable-modern = "on"
      QTREE
    end

    let(:transitional_qtree) do
      <<~QTREE
        dev: virtio-net-pci, id=net0
          disable-legacy = "off"
          disable-modern = "off"
      QTREE
    end

    it 'passes when qtree matches modern' do
      expect { described_class.validate_qtree!(modern_qtree, 'virtio-net-pci', 'modern') }
        .not_to raise_error
    end

    it 'passes when qtree matches legacy' do
      expect { described_class.validate_qtree!(legacy_qtree, 'virtio-net-pci', 'legacy') }
        .not_to raise_error
    end

    it 'passes when qtree matches transitional' do
      expect { described_class.validate_qtree!(transitional_qtree, 'virtio-net-pci', 'transitional') }
        .not_to raise_error
    end

    it 'raises when mode does not match' do
      expect { described_class.validate_qtree!(modern_qtree, 'virtio-net-pci', 'legacy') }
        .to raise_error(AutoHCK::AutoHCKError, /no virtio-net-pci node/)
    end

    it 'raises when device type not found in qtree' do
      expect { described_class.validate_qtree!(modern_qtree, 'virtio-blk-pci', 'modern') }
        .to raise_error(AutoHCK::AutoHCKError, /not found in qtree/)
    end

    it 'raises when qtree is empty' do
      expect { described_class.validate_qtree!('', 'virtio-net-pci', 'modern') }
        .to raise_error(AutoHCK::AutoHCKError, /qtree output is empty/)
    end

    it 'raises when device type is empty' do
      expect { described_class.validate_qtree!(modern_qtree, '', 'modern') }
        .to raise_error(AutoHCK::AutoHCKError, /device_type is not set/)
    end

    it 'raises when mode is empty' do
      expect { described_class.validate_qtree!(modern_qtree, 'virtio-net-pci', '') }
        .to raise_error(AutoHCK::AutoHCKError, /virtio_mode is not set/)
    end
  end
end
