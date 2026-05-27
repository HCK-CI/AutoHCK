# frozen_string_literal: true

require_relative '../../lib/all'

PLATFORM_FIELD_NAMES = AutoHCK::Models::HLKPlatform.props.keys.map(&:to_s).freeze
CLIENT_FIELD_NAMES = AutoHCK::Models::HLKClient.props.keys.map(&:to_s).freeze
CLIENTS_OPTIONS_FIELD_NAMES = AutoHCK::Models::HLKPlatformClientsOptions.props.keys.map(&:to_s).freeze
NESTED_PLATFORM_KEYS = %w[clients clients_options].freeze
PLATFORMS_GLOB = File.join(AutoHCK::HCKTest::PLATFORMS_JSON_DIR, '*.json').freeze

def platform_json_field_names_in(hash, allowed_names)
  allowed_names.select { |name| hash.key?(name) }
end

def expect_parsed_fields_match_json!(parsed, raw_hash, field_names)
  field_names.each do |name|
    expect(parsed.public_send(name)).to eq(raw_hash[name])
  end
end

def register_platform_fields_examples(raw)
  platform_fields = platform_json_field_names_in(raw, PLATFORM_FIELD_NAMES - NESTED_PLATFORM_KEYS)
  return unless platform_fields.any?

  it 'parses platform fields from JSON' do
    expect_parsed_fields_match_json!(platform, raw, platform_fields)
  end
end

def register_clients_options_examples(raw)
  clients_options_raw = raw['clients_options']
  return unless clients_options_raw.is_a?(Hash)

  clients_options_fields = platform_json_field_names_in(clients_options_raw, CLIENTS_OPTIONS_FIELD_NAMES)
  return unless clients_options_fields.any?

  it 'parses clients_options fields from JSON' do
    expect_parsed_fields_match_json!(platform.clients_options, clients_options_raw, clients_options_fields)
  end
end

def register_clients_keys_example(raw)
  return unless raw.key?('clients')

  it 'parses clients keys from JSON' do
    expect(platform.clients.keys.sort).to eq(raw['clients'].keys.sort)
  end
end

def register_client_fields_examples(raw)
  raw.fetch('clients', {}).each do |client_id, client_raw|
    client_fields = platform_json_field_names_in(client_raw, CLIENT_FIELD_NAMES)
    next if client_fields.empty?

    it "parses client #{client_id} fields from JSON" do
      client = platform.clients.fetch(client_id)
      expect_parsed_fields_match_json!(client, client_raw, client_fields)
    end
  end
end

def define_hlk_platform_json_file_examples(basename, json_path, raw)
  describe basename do
    let(:platform) { AutoHCK::Models::HLKPlatform.from_json_file(json_path) }

    register_platform_fields_examples(raw)
    register_clients_options_examples(raw)
    register_clients_keys_example(raw)
    register_client_fields_examples(raw)
  end
end

describe 'HLK platform JSON' do
  Dir[PLATFORMS_GLOB].each do |json_path|
    raw = JSON.parse(File.read(json_path))
    define_hlk_platform_json_file_examples(File.basename(json_path), json_path, raw)
  end
end
