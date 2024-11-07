require_relative '../lib/all'

JSON_TYPES_MAP = {
  './lib/engines/hcktest/drivers/*.json' => AutoHCK::Models::Driver,
  './lib/engines/hckinstall/kits/*.json' => AutoHCK::Models::Kit,
  './lib/engines/hcktest/hcktest.json' => AutoHCK::Models::HCKTestConfig,
  './svvp.json' => AutoHCK::Models::SVVPConfig,
  './lib/setupmanagers/qemuhck/devices/*.json' => AutoHCK::Models::QemuHCKDevice
}.freeze

describe 'srb_json_load' do
  Dir['./**/*.json'].each do |json_file|
    it json_file.to_s do
      pair = JSON_TYPES_MAP.find { File.fnmatch(_1[0], json_file) }

      if pair.nil?
        pending("NO TYPE FOR #{json_file}")
        raise
      end

      expect { pair[1].from_json_file(json_file) }.not_to raise_error
    end
  end
end
