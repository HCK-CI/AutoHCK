# frozen_string_literal: true

require_relative '../lib/all'
require_relative '../lib/cli'

describe AutoHCK::CliCommonOptions do
  subject(:options) { described_class.new }

  describe '#apply_device_option' do
    it 'stores QEMU-style device properties' do
      options.apply_device_option('virtio-net-pci,disable-legacy=on')

      expect(options.device_options).to eq('virtio-net-pci' => 'disable-legacy=on')
    end

    it 'concatenates repeated options for the same device' do
      options.apply_device_option('virtio-net-pci,disable-legacy=on')
      options.apply_device_option('virtio-net-pci,disable-modern=off')

      expect(options.device_options).to eq(
        'virtio-net-pci' => 'disable-legacy=on,disable-modern=off'
      )
    end

    it 'keeps options for different devices separate' do
      options.apply_device_option('virtio-net-pci,disable-legacy=on')
      options.apply_device_option('virtio-blk-pci,discard_granularity=4096')

      expect(options.device_options).to eq(
        'virtio-net-pci' => 'disable-legacy=on',
        'virtio-blk-pci' => 'discard_granularity=4096'
      )
    end

    it 'strips a leading comma from the properties part' do
      options.apply_device_option('virtio-net-pci,,disable-legacy=on')

      expect(options.device_options).to eq('virtio-net-pci' => 'disable-legacy=on')
    end

    it 'raises on missing device or properties' do
      expect { options.apply_device_option('virtio-net-pci') }
        .to raise_error(AutoHCK::AutoHCKError, /Invalid --device-option/)
      expect { options.apply_device_option(',disable-legacy=on') }
        .to raise_error(AutoHCK::AutoHCKError, /Invalid --device-option/)
      expect { options.apply_device_option('virtio-net-pci,') }
        .to raise_error(AutoHCK::AutoHCKError, /Invalid --device-option/)
    end
  end
end
