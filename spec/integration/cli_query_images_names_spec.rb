# frozen_string_literal: true

require_relative '../../lib/all'

REPO_ROOT = File.expand_path('../..', __dir__)

# rubocop:disable Metrics/BlockLength
describe 'CLI and Project#prepare query mode (images-names)', :integration do
  around do |example|
    previous_override = AutoHCK::Helper::Json.instance_variable_get(:@json_override_file)
    Dir.chdir(REPO_ROOT) { example.run }
  ensure
    AutoHCK::Helper::Json.instance_variable_set(:@json_override_file, previous_override)
  end

  before do
    skip 'repo config.json missing' unless File.exist?(File.join(REPO_ROOT, 'config.json'))
    platform_json = File.join(REPO_ROOT, 'lib/engines/hcktest/platforms/Win10_2004x64.json')
    skip 'Win10_2004x64 platform fixture missing' unless File.exist?(platform_json)
  end

  it 'parses CLI argv, runs prepare, and writes images-names to the query output file' do
    Dir.mktmpdir('images_names_query') do |tmp|
      out = File.join(tmp, 'names.txt')
      argv = [
        'test', '-p', 'Win10_2004x64',
        '--query', 'images-names',
        '--query-output-file', out
      ]

      cli = AutoHCK::CLI.new
      cli.parse(argv)

      expect(cli.mode).to eq('test')
      expect(cli.test.query).to eq('images-names')
      expect(cli.test.platform).to eq('Win10_2004x64')

      AutoHCK::ResourceScope.open do |scope|
        project = AutoHCK::Project.new(scope, cli)
        expect(project.prepare).to be(false)
        expect(project.engine).to be_nil
      end

      expected = <<~TEXT.chomp
        Studio image: HLK2004.qcow2
        Client CL1: HLK2004-C1-Win10_2004x64.qcow2
        Client CL2: HLK2004-C2-Win10_2004x64.qcow2
      TEXT
      expect(File.read(out).strip).to eq(expected)
    end
  end

  it 'logs image names to the project string log when query_output_file is omitted' do
    cli = AutoHCK::CLI.new
    cli.parse(['test', '-p', 'Win10_2004x64', '--query', 'images-names'])

    AutoHCK::ResourceScope.open do |scope|
      project = AutoHCK::Project.new(scope, cli)
      expect(project.prepare).to be(false)
      log = project.string_log.string
      expect(log).to include('Studio image: HLK2004.qcow2')
      expect(log).to include('Client CL1: HLK2004-C1-Win10_2004x64.qcow2')
      expect(log).to include('Client CL2: HLK2004-C2-Win10_2004x64.qcow2')
    end
  end

  it 'raises AutoHCKError for an unknown query' do
    cli = AutoHCK::CLI.new
    cli.parse(['test', '-p', 'Win10_2004x64', '--query', 'unknown-query'])

    expect do
      AutoHCK::ResourceScope.open do |scope|
        AutoHCK::Project.new(scope, cli).prepare
      end
    end.to raise_error(AutoHCK::AutoHCKError, /Unknown query: unknown-query/)
  end
end
# rubocop:enable Metrics/BlockLength
