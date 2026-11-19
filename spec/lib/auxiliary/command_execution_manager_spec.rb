# frozen_string_literal: true

require_relative '../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::CommandExecutionManager do
  # build_qmp_arguments is pure apart from its arguments (the constructor's
  # sorbet sig requires a real AutoHCK::Project), so test it on an
  # allocated instance instead of building one.
  subject(:manager) { described_class.allocate }

  let(:map) { AutoHCK::ReplacementMap.new('@bus@' => 'root5.0', '@slot@' => '3') }

  def qmp_with(arguments)
    Struct.new(:arguments).new(arguments)
  end

  describe '#build_qmp_arguments' do
    it 'returns nil for a command without arguments' do
      expect(manager.send(:build_qmp_arguments, qmp_with(nil), map, 'query-pci', 'CL1')).to be_nil
    end

    it 'substitutes and coerces numeric values' do
      arguments = manager.send(:build_qmp_arguments, qmp_with({ 'bus' => '@bus@', 'slot' => '@slot@' }),
                               map, 'device_add', 'CL1')
      expect(arguments).to eq('bus' => 'root5.0', 'slot' => 3)
    end

    it 'raises with command and machine context when a placeholder survives substitution' do
      error = begin
        manager.send(:build_qmp_arguments, qmp_with({ 'bus' => '@spare_pcie_root_port_2@' }),
                     map, 'device_add', 'CL1')
        nil
      rescue AutoHCK::EngineError => e
        e
      end
      expect(error).to be_a(AutoHCK::EngineError)
      expect(error.message).to include("QMP command 'device_add' on CL1")
      expect(error.message).to include('@spare_pcie_root_port_2@')
    end
  end
end
# rubocop:enable Metrics/BlockLength
