# frozen_string_literal: true

require_relative '../../../lib/all'

describe AutoHCK::CommandExecutionManager do
  # validate_qmp_placeholders! is pure (constant + arguments only), and the
  # constructor's sorbet sig requires a real AutoHCK::Project, so test it on
  # an allocated instance instead of building one.
  subject(:manager) { described_class.allocate }

  describe '#validate_qmp_placeholders!' do
    it 'raises naming every unsubstituted placeholder in nested arguments' do
      args = {
        'bus' => '@spare_pcie_root_port_2@',
        'drive' => { 'file' => { 'filename' => '/ws/virtio_blk_@storage_dev_id@_dev' } }
      }
      error = begin
        manager.send(:validate_qmp_placeholders!, 'device_add', args, 'CL1')
        nil
      rescue AutoHCK::EngineError => e
        e
      end
      expect(error).to be_a(AutoHCK::EngineError)
      expect(error.message).to include("QMP command 'device_add' on CL1")
      expect(error.message).to include('@spare_pcie_root_port_2@')
      expect(error.message).to include('@storage_dev_id@')
    end

    it 'passes when every placeholder was substituted' do
      args = { 'bus' => 'root5.0', 'drive' => { 'file' => { 'filename' => '/ws/01_dev' } } }
      expect { manager.send(:validate_qmp_placeholders!, 'device_add', args, 'CL1') }.not_to raise_error
    end

    it 'passes when arguments are nil (command without arguments)' do
      expect { manager.send(:validate_qmp_placeholders!, 'query-pci', nil, 'CL1') }.not_to raise_error
    end
  end
end
