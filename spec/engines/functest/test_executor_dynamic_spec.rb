# frozen_string_literal: true

require_relative '../../../lib/all'
require_relative '../../../lib/engines/functest/test_context'
require_relative '../../../lib/engines/functest/test_loader'
require_relative '../../../lib/engines/functest/step_handler'
require_relative '../../../lib/engines/functest/parallel_branch_runner'
require_relative '../../../lib/engines/functest/test_executor'
require 'tmpdir'

describe AutoHCK::Functest::TestExecutor do
  let(:logger) { MonoLogger.new(File::NULL) }
  let(:test_options) { double('test_options', platform: 'Win2025x64') }
  let(:options) { double('options', test: test_options) }
  let(:workspace_path) { Dir.mktmpdir('functest_ws') }
  let(:project) do
    instance_double(
      AutoHCK::Project,
      logger: logger,
      options: options,
      workspace_path: workspace_path,
      result_uploader: instance_double(AutoHCK::ResultUploader, upload_file: nil),
      generate_result_report: nil,
      generate_junit: nil,
      update_test_stats: nil
    )
  end
  let(:client) do
    instance_double(
      AutoHCK::FunctestClient,
      name: 'client1',
      replacement_map: {},
      reboot_clean: nil,
      reboot_from_snapshot: nil,
      save_snapshot: nil
    )
  end
  let(:tools) { instance_double(AutoHCK::FunctestTools) }
  let(:command_execution_manager) do
    instance_double(
      AutoHCK::CommandExecutionManager,
      scope_to_test: nil,
      primary_machine: 'client1'
    )
  end
  let(:engine) do
    instance_double(
      AutoHCK::FunctestEngine,
      project: project,
      extensions: [],
      suite: nil,
      default_timeout: 30
    )
  end
  let(:run_context) do
    described_class::RunContext.new(
      clients: [client],
      tools: tools,
      command_execution_manager: command_execution_manager
    )
  end
  let(:executor) { described_class.new(engine, run_context) }

  after do
    FileUtils.remove_entry(workspace_path) if Dir.exist?(workspace_path)
  end

  def build_dynamic_test(dir)
    cases = File.join(dir, 'cases')
    FileUtils.mkdir_p(cases)
    File.write(File.join(cases, 'dyn.json'), <<~JSON)
      { "name": "dyn", "dynamic": true }
    JSON
    File.write(File.join(cases, 'dyn.rb'), <<~RUBY)
      module AutoHCK
        module Functest
          module DynamicTests
            def self.dyn
              Class.new(AutoHCK::Functest::DynamicTest) do
                def run_pre_test_commands(_test)
                  @pre_called = true
                end

                def execute_test_steps(_test, result)
                  result[:steps] << { index: 0, description: 'dynamic step', status: 'passed' }
                end

                def run_cleanup(_test)
                  @cleanup_called = true
                end

                attr_reader :pre_called, :cleanup_called
              end
            end
          end
        end
      end
    RUBY

    loader = AutoHCK::Functest::TestLoader.new(project, dir)
    loader.load_test('dyn')
  end

  it 'delegates pre/steps/cleanup to the dynamic implementation' do
    Dir.mktmpdir('functest_exec_dyn') do |dir|
      test = build_dynamic_test(dir)
      allow(AutoHCK::TestSummaryLog).to receive(:write)
      allow(AutoHCK::MemoryDumpCollector).to receive(:new)
        .and_return(instance_double(AutoHCK::MemoryDumpCollector, collect: nil))

      summary = executor.execute_tests([test])
      impl = executor.send(:dynamic_impl_for, test)

      expect(summary[:passed]).to eq(1)
      expect(summary[:failed]).to eq(0)
      expect(summary[:results].first[:steps].first[:description]).to eq('dynamic step')
      expect(impl.pre_called).to be(true)
      expect(impl.cleanup_called).to be(true)
    end
  end
end
