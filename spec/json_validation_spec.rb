require 'json'
require 'jtd'

describe 'json_validation' do
  Dir['./**/*.json'].each do |json_file|
    next if json_file.include? 'jtd.json'


    name = File.basename(json_file, '.json')
    dir = File.dirname(json_file)
    it json_file.to_s do
      json_schema_candidates = [
        "#{dir}/#{name}.jtd.json",
        "#{dir}/jtd.json",
      ]

      json_schemas = json_schema_candidates.filter_map do |f|
        JSON.load_file(f)
      rescue Errno::ENOENT
      end

      if json_schemas.empty?
        pending("NO SCHEMA FOR #{name} -> #{json_schema_candidates}")
        raise
      end

      json_data = JSON.load_file(json_file)
      schema = JTD::Schema.from_hash(json_schemas.first)
      schema.verify()

      result = JTD::validate(schema, json_data)
      expect(result).to eq([])
    end
  end
end
