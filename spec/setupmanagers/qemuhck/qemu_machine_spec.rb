# frozen_string_literal: true

require_relative '../../../lib/all'

describe AutoHCK::QemuMachine do
  describe '#validate_run_opts' do
    let(:machine) { described_class.allocate }

    it 'returns default run options merged with an empty hash' do
      expect(machine.send(:validate_run_opts, {})).to eq(described_class::DEFAULT_RUN_OPTIONS)
    end

    it 'merges given options over defaults' do
      merged = machine.send(:validate_run_opts, { keep_alive: true, dump_only: true })

      expect(merged[:keep_alive]).to be(true)
      expect(merged[:dump_only]).to be(true)
      expect(merged[:create_snapshot]).to be(true)
    end

    it 'raises MachineRunError when an unknown option key is present' do
      expect { machine.send(:validate_run_opts, { unknown_key: true }) }
        .to raise_error(AutoHCK::MachineRunError, /unknown_key/)
    end

    it 'lists every unknown key in the error message' do
      expect { machine.send(:validate_run_opts, { bad_one: 1, bad_two: 2 }) }
        .to raise_error(AutoHCK::MachineRunError) do |err|
          expect(err.message).to include('bad_one')
          expect(err.message).to include('bad_two')
        end
    end
  end

  describe '#device_options_replacement_map' do
    let(:machine) { described_class.allocate }

    before do
      machine.instance_variable_set(:@options, {
                                      'device_options' => {
                                        'virtio-net-pci' => 'disable-legacy=on,disable-modern=off',
                                        'virtio-blk-pci' => ',discard_granularity=4096'
                                      }
                                    })
    end

    it 'prepends a comma when options are present' do
      expect(machine.send(:device_options_replacement_map, 'virtio-net-pci'))
        .to eq('@device_options@' => ',disable-legacy=on,disable-modern=off')
    end

    it 'does not double the leading comma' do
      expect(machine.send(:device_options_replacement_map, 'virtio-blk-pci'))
        .to eq('@device_options@' => ',discard_granularity=4096')
    end

    it 'returns an empty string when the device has no options' do
      expect(machine.send(:device_options_replacement_map, 'e1000e'))
        .to eq('@device_options@' => '')
    end
  end
end
