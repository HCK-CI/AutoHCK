require 'json'

require './lib/models/driver'

JSON_TYPES_MAP = {
  './lib/engines/hcktest/drivers/*.json' => AutoHCK::Models::Driver,
}.freeze

describe 'srb_json_load' do
  Dir['./**/*.json'].each do |json_file|
    next if json_file.include? 'jtd.json'

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
