# frozen_string_literal: true

require_relative '../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::CmdRun, :linux_process do
  let(:logger_io) { StringIO.new }
  let(:logger) { MonoLogger.new(logger_io) }

  def new_cmd(scope, *args, **kwargs)
    described_class.new(scope, logger, *args, **kwargs)
  end

  describe '#initialize and #close' do
    it 'runs a successful argv-style command and reports exit 0' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/true')
        expect(cmd.close.exitstatus).to be_zero
      end
      expect(logger_io.string).to include('Run command:')
      expect(logger_io.string).to include('finished with code 0')
    end

    it 'records a multi-argument command using shelljoin in the log line' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/echo', 'hi')
        cmd.close
      end
      joined = ['/bin/echo', 'hi'].shelljoin
      expect(logger_io.string).to include("Run command: #{joined}")
    end

    it 'raises CmdRunError when the command fails and exception is true' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/false')
        expect { cmd.close }.to raise_error(AutoHCK::CmdRunError, /Failed to run \(PID/)
        expect(logger_io.string).to include('Run command:')
      end
    end

    it 'does not raise when exception is false even if exit status is non-zero' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/false', exception: false)
        expect(cmd.close.exitstatus).to eq(1)
      end
      expect(logger_io.string).to include('finished with code 1')
    end

    it 'returns the same Process::Status on a second close' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/true')
        first = cmd.close
        expect(cmd.close).to equal(first)
      end
    end

    it 'leaves status available after a rescued CmdRunError' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/false', exception: true)
        expect { cmd.close }.to raise_error(AutoHCK::CmdRunError)
        expect(cmd.close.exitstatus).to eq(1)
      end
    end
  end

  describe 'spawn options' do
    it 'passes chdir through to spawn' do
      Dir.mktmpdir('cmd_run_chdir') do |dir|
        AutoHCK::ResourceScope.open([]) do |scope|
          cmd = new_cmd(scope, '/bin/pwd', chdir: dir)
          cmd.close
        end
        expect(logger_io.string).to include("stdout: #{dir}")
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
