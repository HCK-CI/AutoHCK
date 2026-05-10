# frozen_string_literal: true

require_relative '../../lib/all'

# Integration scenarios: temp files, full Json + Config stack.
# rubocop:disable Metrics/BlockLength
describe 'JSON override mechanism (Helper::Json + Config)', :integration do
  around do |example|
    previous = AutoHCK::Helper::Json.instance_variable_get(:@json_override_file)
    example.run
  ensure
    AutoHCK::Helper::Json.instance_variable_set(:@json_override_file, previous)
  end

  describe 'read_json' do
    it 'deep-merges entries keyed by the same path passed to read_json' do
      Dir.mktmpdir('json_override') do |dir|
        base_path = File.join(dir, 'data.json')
        override_path = File.join(dir, 'custom_override.json')

        File.write(
          base_path,
          JSON.dump(
            'top' => { 'a' => 1, 'keep' => true },
            'leaf' => 0,
            'only_in_base' => 'preserved'
          )
        )
        File.write(
          override_path,
          JSON.dump(base_path => { 'top' => { 'b' => 2 }, 'leaf' => 99 })
        )

        AutoHCK::Helper::Json.update_json_override(override_path)
        data = AutoHCK::Helper::Json.read_json(base_path)

        expect(data['top']).to eq('a' => 1, 'b' => 2, 'keep' => true)
        expect(data['leaf']).to eq(99)
        expect(data['only_in_base']).to eq('preserved')
      end
    end

    it 'skips merging when the override file path is set but the file is missing' do
      Dir.mktmpdir('no_override_file') do |dir|
        base_path = File.join(dir, 'only.json')
        File.write(base_path, JSON.dump('x' => 1))

        AutoHCK::Helper::Json.update_json_override(File.join(dir, 'missing_override.json'))
        data = AutoHCK::Helper::Json.read_json(base_path)

        expect(data).to eq('x' => 1)
      end
    end

    it 'leaves the base unchanged when the override has no entry for that json path' do
      Dir.mktmpdir('override_other_key') do |dir|
        base_path = File.join(dir, 'target.json')
        override_path = File.join(dir, 'override.json')

        File.write(base_path, JSON.dump('only' => 'base'))
        File.write(override_path, JSON.dump('other_file.json' => { 'noise' => true }))

        AutoHCK::Helper::Json.update_json_override(override_path)
        data = AutoHCK::Helper::Json.read_json(base_path)

        expect(data).to eq('only' => 'base')
      end
    end
  end

  describe 'Config.read' do
    it 'applies overrides when keys use config.json like production' do
      Dir.mktmpdir('config_override') do |dir|
        Dir.chdir(dir) do
          File.write(
            'config.json',
            JSON.dump(
              'workspace_path' => '/original',
              'nested' => { 'k' => 1, 'untouched' => true },
              'only_in_config' => 'still_here'
            )
          )
          File.write(
            'my_override.json',
            JSON.dump('config.json' => { 'workspace_path' => '/overridden', 'nested' => { 'k' => 2, 'extra' => 3 } })
          )

          AutoHCK::Helper::Json.update_json_override(File.expand_path('my_override.json'))
          cfg = AutoHCK::Config.read

          expect(cfg['workspace_path']).to eq('/overridden')
          expect(cfg['nested']).to eq('k' => 2, 'extra' => 3, 'untouched' => true)
          expect(cfg['only_in_config']).to eq('still_here')
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
