# frozen_string_literal: true

require_relative '../../../../lib/all'
require_relative '../../../../lib/engines/functest/test_context'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::Functest::TestContext do
  let(:logger_io) { StringIO.new }
  let(:logger) { MonoLogger.new(logger_io) }
  let(:project) { Struct.new(:logger).new(logger) }
  let(:baseline) { { '@workspace@' => '/tmp/ws' } }

  subject(:context) { described_class.new(project, baseline) }

  describe '#reset_test_variables!' do
    it 'drops variables set by the previous test' do
      context.lock_baseline!
      context.set_variable('disk_count', '23')
      expect(context.substitute_variables('@disk_count@')).to eq('23')

      context.reset_test_variables!

      expect(context.substitute_variables('@disk_count@')).to eq('@disk_count@')
    end

    it 'keeps engine-level variables (constructor map, setup_test_context, test params)' do
      context.set_variable('driver_module', 'vioscsi')
      context.set_variable('disk_count', '23')
      context.lock_baseline!
      context.set_variable('target_disk_number', '2')

      context.reset_test_variables!

      expect(context.substitute_variables('@workspace@')).to eq('/tmp/ws')
      expect(context.substitute_variables('@driver_module@')).to eq('vioscsi')
      expect(context.substitute_variables('@target_disk_number@')).to eq('@target_disk_number@')
    end

    it 'is a no-op until lock_baseline! was called' do
      context.set_variable('driver_module', 'vioscsi')

      context.reset_test_variables!

      expect(context.substitute_variables('@driver_module@')).to eq('vioscsi')
    end

    it 'drops only variables set since the last reset' do
      context.lock_baseline!
      context.set_variable('disk_count', '23')
      context.reset_test_variables!
      context.set_variable('target_disk_number', '2')

      expect(context.substitute_variables('@target_disk_number@')).to eq('2')
      expect(context.substitute_variables('@disk_count@')).to eq('@disk_count@')

      context.reset_test_variables!
      expect(context.substitute_variables('@target_disk_number@')).to eq('@target_disk_number@')
    end

    it 'makes step variable lookups warn again for dropped variables' do
      context.lock_baseline!
      context.set_variable('disk_count', '23')
      context.reset_test_variables!

      context.substitute_variables('x @disk_count@ x', { '@disk_count@' => 'disk_count' })
      expect(logger_io.string).to include("Variable 'disk_count' not found")
    end
  end
end
# rubocop:enable Metrics/BlockLength
