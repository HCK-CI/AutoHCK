require 'json'
require_relative '../lib/all'

describe 'sysinfo_parser' do
  spec_path = 'spec/sysinfo_parser_spec'
  sysinfos = "#{spec_path}/sysinfo_*.txt"

  Dir[sysinfos].each do |sysinfo|
    name = File.basename(sysinfo)
    json_name = "#{spec_path}/#{name.split('.')[0]}.json"

    data = File.read(sysinfo)
    json_data = JSON.parse(File.read(json_name))

    parser = AutoHCK::SysInfoParser.new

    it name.to_s do
      result = parser.parse(data)
      expect(result).to eq(json_data)
    end
  end
end
