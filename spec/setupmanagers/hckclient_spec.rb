# frozen_string_literal: true

require_relative '../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::HCKClient do
  # The studio's pools and the tools that move machines between them.
  let(:pools) { { 'CL1' => 'Default Pool' } }
  let(:studio) do
    pools_ref = pools
    double('studio', list_pools: nil).tap do |studio|
      allow(studio).to receive(:list_pools) do
        pools_ref.group_by { |_, pool| pool }.map do |pool, entries|
          { 'name' => pool, 'machines' => entries.map { |machine, _| { 'name' => machine } } }
        end
      end
    end
  end
  let(:tools) do
    pools_ref = pools
    double('tools').tap do |tools|
      allow(tools).to receive(:move_machine) { |machine, _from, to| pools_ref[machine] = to }
    end
  end

  def client_with(run_opts)
    client = described_class.allocate
    project = double('project', engine_tag: 'project', logger: Logger.new(File::NULL))
    { project:, logger: project.logger, studio:, tools:, name: 'CL1', run_opts: }.each do |var, value|
      client.instance_variable_set(:"@#{var}", value)
    end
    stub_setup_steps(client)
  end

  def stub_setup_steps(client)
    %i[return_when_client_up prepare_machine configure_machine run_post_start_commands
       add_target_to_project].each { allow(client).to receive(_1) }
    allow(client).to receive(:pool_only_client?).and_return(false)
    allow(client).to receive(:move_machine_to_pool) { pools['CL1'] = 'project' }
    client
  end

  describe '#configure_fresh' do
    it 'prepares a fresh client' do
      client = client_with({})
      client.configure_fresh(run_only: false)

      expect(client).to have_received(:prepare_machine)
      expect(pools['CL1']).to eq('project')
    end

    it 'prepares a fresh client that a failed attempt left in the project pool' do
      pools['CL1'] = 'project'
      client = client_with({})
      client.configure_fresh(run_only: false)

      expect(tools).to have_received(:move_machine).with('CL1', 'project', 'Default Pool')
      expect(client).to have_received(:prepare_machine)
      expect(pools['CL1']).to eq('project')
    end

    it 'does not prepare a client booted from the snapshot of a prepared setup' do
      pools['CL1'] = 'project'
      client = client_with({ boot_from_snapshot: true })
      client.configure_fresh(run_only: false)

      expect(client).not_to have_received(:prepare_machine)
      expect(tools).not_to have_received(:move_machine)
    end
  end
end
# rubocop:enable Metrics/BlockLength
