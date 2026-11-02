# frozen_string_literal: true

require 'tmpdir'
require 'json'
require 'logger'

require_relative '../../../../lib/all'

describe AutoHCK::ExtraSoftwareManager do
  subject(:manager) { described_class.new(project) }

  let(:logger) { Logger.new(IO::NULL) }

  let(:engine_platform) do
    instance_double(AutoHCK::Models::HLKPlatform, client_arch: 'amd64', clients: {})
  end

  let(:project) do
    instance_double(
      AutoHCK::Project,
      logger: logger,
      config: { 'extra_software' => '/does/not/matter' },
      engine_platform: engine_platform
    )
  end

  def write_config(dir, arch, file_name, download_url)
    config_dir = File.join(dir, 'extra-software', 'openssh')
    FileUtils.mkdir_p(config_dir)
    config = {
      'install_cmd' => 'powershell.exe',
      'install_args' => '-File install-openssh.ps1',
      'install_dest' => 'all',
      'install_time' => { 'kit' => 'before', 'driver' => 'before' },
      'file_name' => file_name,
      'download_url' => download_url
    }
    File.write(File.join(config_dir, "#{arch}-config.json"), JSON.generate(config))
    config_dir
  end

  describe '#prepare_bundled_software' do
    it 'downloads the arch-matched payload when it is not already present' do
      Dir.mktmpdir do |dir|
        config_dir = write_config(dir, 'amd64', 'OpenSSH-Win64.zip', 'https://example/OpenSSH-Win64.zip')

        downloader = instance_double(AutoHCK::Downloader)
        expect(AutoHCK::Downloader).to receive(:new).and_return(downloader)
        expect(downloader).to receive(:download)
          .with('https://example/OpenSSH-Win64.zip', File.join(config_dir, 'OpenSSH-Win64.zip'))

        manager.prepare_bundled_software('openssh', dir, 'HLK', 'install')
      end
    end

    it 'skips the download when the payload already exists' do
      Dir.mktmpdir do |dir|
        config_dir = write_config(dir, 'amd64', 'OpenSSH-Win64.zip', 'https://example/OpenSSH-Win64.zip')
        File.write(File.join(config_dir, 'OpenSSH-Win64.zip'), 'cached')

        expect(AutoHCK::Downloader).not_to receive(:new)

        manager.prepare_bundled_software('openssh', dir, 'HLK', 'install')
      end
    end

    it 'does nothing when the bundled package folder is missing' do
      Dir.mktmpdir do |dir|
        expect(AutoHCK::Downloader).not_to receive(:new)

        manager.prepare_bundled_software('openssh', dir, 'HLK', 'install')
      end
    end
  end
end
