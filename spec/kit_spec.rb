require_relative '../lib/all'

describe 'kit_spec' do
  Dir['./lib/engines/hckinstall/kits/*.json'].each do |json_file|
    kit_url = AutoHCK::Models::Kit.from_json_file(json_file).download_url
    next if kit_url.nil?

    it "Kit for #{json_file} can be downloaded" do
      content = String.new

      HTTPClient.get_content(kit_url) do |chunk|
        content << chunk
        break if content.size > 32_773
      end

      file_type = nil
      file_type = 'exe' if content[0..1] == 'MZ'
      file_type = 'iso' if content[32_769..32_773] == 'CD001'

      expect(%w[exe iso]).to include(file_type)
    end
  end
end
