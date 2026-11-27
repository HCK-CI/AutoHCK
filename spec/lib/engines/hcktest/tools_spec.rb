# frozen_string_literal: true

require_relative '../../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::Tools do
  # The HLK controller as RToolsHCK sees it. Like HLK's MoveMachineTo, a move
  # commits the new pool first and can fail afterwards, when it sets the
  # machine's crash dump property.
  let(:controller_class) do
    Class.new do
      attr_reader :pools, :moves

      def initialize(property_failures)
        @pools = { 'CL1' => 'Default Pool' }
        @property_failures = property_failures
        @moves = []
      end

      def move_machine(machine, from, to)
        @moves << [from, to]
        return failure("Provided machine's name is not valid, aborting...") unless @pools[machine] == from

        @pools[machine] = to
        return { 'result' => 'Success' } unless @property_failures.positive?

        @property_failures -= 1
        failure("Could not set this property on machine (#{machine}).")
      end

      def list_pools
        content = @pools.group_by { |_, pool| pool }.map do |pool, entries|
          { 'name' => pool, 'machines' => entries.map { |machine, _| { 'name' => machine } } }
        end
        { 'result' => 'Success', 'content' => content }
      end

      private

      def failure(message)
        { 'result' => 'Failure', 'message' => message }
      end
    end
  end

  def tools_for(controller)
    tools = described_class.allocate
    tools.instance_variable_set(:@logger, Logger.new(File::NULL))
    tools.instance_variable_set(:@tools, AutoHCK::Tools::ThreadSafe.new(controller, Mutex.new))
    allow(tools).to receive(:sleep)
    tools
  end

  describe '#move_machine' do
    it 'moves the machine' do
      controller = controller_class.new(0)
      tools_for(controller).move_machine('CL1', 'Default Pool', 'project')

      expect(controller.pools['CL1']).to eq('project')
      expect(controller.moves).to eq([['Default Pool', 'project']])
    end

    it 'makes the whole move again when the property write failed after the pool change' do
      controller = controller_class.new(1)
      tools_for(controller).move_machine('CL1', 'Default Pool', 'project')

      expect(controller.pools['CL1']).to eq('project')
      expect(controller.moves).to eq([['Default Pool', 'project'], ['project', 'Default Pool'],
                                      ['Default Pool', 'project']])
    end

    it 'gives up after the retries' do
      controller = controller_class.new(described_class::ACTION_RETRIES * 2)

      expect { tools_for(controller).move_machine('CL1', 'Default Pool', 'project') }
        .to raise_error(AutoHCK::Tools::ToolsHCKError, /Could not set this property/)
    end
  end
end
# rubocop:enable Metrics/BlockLength
