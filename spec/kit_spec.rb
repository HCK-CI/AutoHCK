require_relative '../lib/all'
require 'digest'

describe 'kit_spec' do
  Dir['./lib/engines/hckinstall/kits/*.json'].each do |json_file|
    kit = AutoHCK::Models::Kit.from_json_file(json_file)
    kit_url = kit.download_url
    next if kit_url.nil?

    it "Kit for #{json_file} can be downloaded" do
      content = String.new

      file_type = nil
      HTTPClient.get_content(kit_url) do |chunk|
        content << chunk
        file_type ||= 'exe' if content[0..1] == 'MZ'
        # For ISOs, we only need the header. For EXEs, we need the whole file for checksum.
        if content.size > 32_773 # Check for ISO header
          file_type ||= 'iso' if content[32_769..32_773] == 'CD001'
          break unless file_type == 'exe'
        end
      end

      expect(%w[exe iso]).to include(file_type)
      expect(Digest::SHA256.hexdigest(content)).to eq(kit.sha256) if file_type == 'exe'
    end
  end
end
