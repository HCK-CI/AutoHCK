require 'json'
require 'json_schemer'

describe 'json_validation' do
  Dir['./**/*.json'].each do |json_file|
    next if json_file.include? 'schema.json'

    name = File.basename(json_file, '.json')
    dir = File.dirname(json_file)
    it json_file.to_s do
      json_schema_candidates = [
        "#{dir}/#{name}.schema.json",
        "#{dir}/schema.json",
      ]

      json_schemas = json_schema_candidates.filter_map do |f|
        File.read(f)
      rescue Errno::ENOENT
      end

      if json_schemas.empty?
        pending("NO SCHEMA FOR #{name} -> #{json_schema_candidates}")
        raise
      end

      json_data = JSON.load_file(json_file)

      result = JSONSchemer.schema(json_schemas.first).validate(json_data)
      expect(result).to contain_exactly()
    end
  end
end
