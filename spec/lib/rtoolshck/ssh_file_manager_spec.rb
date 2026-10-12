# frozen_string_literal: true

require 'tmpdir'

require_relative '../../../lib/all'

describe AutoHCK::SshFileManager do
  subject(:manager) do
    described_class.new(
      addr: '127.0.0.1',
      user: 'Administrator',
      pass: 'PASSWORD',
      port: 22,
      timeout: 1,
      logger_proc: nil
    )
  end

  describe '#exists?' do
    it 'returns false only when Test-Path completes and the path is absent' do
      allow(manager).to receive(:powershell) do |script|
        expect(script).to include('ExpandString')
        ['', 1]
      end

      expect(manager.exists?('${env:SystemRoot}/Minidump')).to be false
    end

    it 'returns true when Test-Path finds the path' do
      allow(manager).to receive(:powershell).and_return(['', 0])

      expect(manager.exists?('C:/present')).to be true
    end

    it 'raises when the probe fails instead of treating the path as absent' do
      allow(manager).to receive(:powershell).and_return(['access denied', 2])

      expect { manager.exists?('C:/bad') }
        .to raise_error(AutoHCK::RToolsHCKError, /Test-Path failed for C:\/bad: access denied/)
    end

    it 'raises when the SSH command ends without an exit status' do
      ssh = instance_double(Net::SSH::Connection::Session, open_channel: nil, loop: nil)
      allow(Net::SSH).to receive(:start).and_return(ssh)

      expect { manager.exists?('C:/file') }
        .to raise_error(AutoHCK::RToolsHCKError, /without an exit status/)
    end

    it 'propagates SSH connection failures instead of reporting the path missing' do
      allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect { manager.exists?('C:/file') }
        .to raise_error(AutoHCK::RToolsHCKError, /SSH connection failed: Errno::ECONNREFUSED/)
    end
  end

  describe '#delete' do
    it 'returns true when the target is already gone or was removed' do
      allow(manager).to receive(:powershell) do |script|
        expect(script).to include('ErrorAction Stop')
        expect(script).to include('Test-Path')
        expect(script).not_to include('SilentlyContinue')
        ['', 0]
      end

      expect(manager.delete('C:/file')).to be true
    end

    it 'raises when Remove-Item fails' do
      allow(manager).to receive(:powershell).and_return(['file in use', 1])

      expect { manager.delete('C:/file') }
        .to raise_error(AutoHCK::RToolsHCKError, /failed to delete C:\/file: file in use/)
    end
  end

  describe '#ensure_remote_directory' do
    it 'raises when New-Item fails' do
      allow(manager).to receive(:powershell) do |script|
        expect(script).to include('New-Item')
        expect(script).to include('ErrorAction Stop')
        ['access denied', 1]
      end

      expect { manager.send(:ensure_remote_directory, 'C:/locked') }
        .to raise_error(AutoHCK::RToolsHCKError, /failed to create directory C:\/locked: access denied/)
    end

    it 'succeeds when New-Item exits zero' do
      allow(manager).to receive(:powershell).and_return(['', 0])

      expect { manager.send(:ensure_remote_directory, 'C:/ok') }.not_to raise_error
    end
  end

  describe '#download' do
    let(:directory_attrs) do
      instance_double(Net::SFTP::Protocol::V01::Attributes, permissions: 0o40755, directory?: true)
    end
    let(:file_attrs) do
      instance_double(Net::SFTP::Protocol::V01::Attributes, permissions: 0o100644, directory?: false)
    end

    it 'downloads a directory tree through one SFTP session' do
      sftp = instance_double(Net::SFTP::Session)
      allow(sftp).to receive(:stat!).with('/C:/logs').and_return(directory_attrs)
      Dir.mktmpdir do |dir|
        local = File.join(dir, 'logs')
        expect(sftp).to receive(:download!).with('/C:/logs', local, { recursive: true })
        expect(Net::SFTP).to receive(:start)
          .with('127.0.0.1', 'Administrator', hash_including(verify_host_key: :never))
          .once
          .and_yield(sftp)

        manager.download('C:/logs', local)
      end
    end

    it 'downloads a file through that same single session' do
      sftp = instance_double(Net::SFTP::Session)
      allow(sftp).to receive(:stat!).with('/C:/logs/a.txt').and_return(file_attrs)
      Dir.mktmpdir do |dir|
        local = File.join(dir, 'a.txt')
        expect(sftp).to receive(:download!).with('/C:/logs/a.txt', local, {})
        expect(Net::SFTP).to receive(:start).once.and_yield(sftp)

        manager.download('C:/logs/a.txt', local)
      end
    end

    it 'resolves guest environment paths before opening SFTP' do
      sftp = instance_double(Net::SFTP::Session)
      allow(manager).to receive(:powershell).and_return(["C:\\Windows\\Minidump\n", 0])
      allow(sftp).to receive(:stat!).with('/C:/Windows/Minidump').and_return(directory_attrs)
      Dir.mktmpdir do |dir|
        local = File.join(dir, 'dumps')
        expect(sftp).to receive(:download!).with('/C:/Windows/Minidump', local, { recursive: true })
        expect(Net::SFTP).to receive(:start).once.and_yield(sftp)

        manager.download('${env:SystemRoot}/Minidump', local)
      end
    end

    it 'propagates SFTP connection failures' do
      allow(Net::SFTP).to receive(:start).and_raise(Errno::ETIMEDOUT)

      expect { manager.download('C:/logs', '/tmp/logs') }
        .to raise_error(AutoHCK::RToolsHCKError, /SSH connection failed: Errno::ETIMEDOUT/)
    end
  end
end

describe AutoHCK::RToolsHCK do
  describe '#close_and_shutdown' do
    it 'drains cached SSH sessions before marking the instance closed' do
      tools = described_class.allocate
      tools.instance_variable_set(:@closed, false)
      tools.instance_variable_set(:@no_studio, false)
      tools.instance_variable_set(:@json, true)
      tools.instance_variable_set(:@log_to_stdout, false)
      tools.instance_variable_set(:@logger, nil)
      file_manager = instance_double(AutoHCK::SshFileManager)
      tools.instance_variable_set(:@machine_fs, { 'CL1' => file_manager })
      tools.instance_variable_set(:@winrm_fs, file_manager)

      allow(tools).to receive(:unload_toolshck)
      allow(tools).to receive(:shutdown)
      allow(tools).to receive(:unload_winrm_ps)
      expect(file_manager).to receive(:close).twice
      expect(tools).to receive(:unload_file_managers).and_wrap_original do |method|
        expect(tools.closed?).to be false
        method.call
      end

      expect(tools.close_and_shutdown).to eq({ 'result' => 'Success' })
      expect(tools.closed?).to be true
      expect(tools.instance_variable_get(:@machine_fs)).to eq({})
      expect(tools.instance_variable_get(:@winrm_fs)).to be_nil
    end
  end

  describe 'SSH action errors' do
    it 'includes connection failures the Tools retry wrappers must see' do
      expect(described_class::SSH_ACTION_ERRORS).to include(
        AutoHCK::RToolsHCKError,
        Net::SSH::Exception,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT,
        Errno::ECONNRESET,
        IOError
      )
    end
  end
end
