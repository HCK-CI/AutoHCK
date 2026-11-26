# frozen_string_literal: true

require_relative '../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::CmdRun, :linux_process do
  let(:logger_io) { StringIO.new }
  let(:logger) { MonoLogger.new(logger_io) }

  def new_cmd(scope, *args, **kwargs)
    described_class.new(scope, logger, *args, **kwargs)
  end

  def wait_for_log_substring(substring, timeout: 2)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until logger_io.string.include?(substring)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise RSpec::Expectations::ExpectationNotMetError,
              "expected log to include #{substring.inspect} within #{timeout}s"
      end
      sleep 0.01
    end
  end

  # Commands are spawned with pgroup: 0, so -pid addresses the whole group,
  # including processes left behind by the command.
  def kill_process_group(pid)
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH
    nil
  end

  describe '#initialize and #close' do
    it 'runs a successful argv-style command and reports exit 0' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/true')
        expect(cmd.close.exitstatus).to be_zero
      end
      wait_for_log_substring('Run command:')
      wait_for_log_substring('finished with code 0')
    end

    it 'records a multi-argument command using shelljoin in the log line' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/echo', 'hi')
        cmd.close
      end
      joined = ['/bin/echo', 'hi'].shelljoin
      wait_for_log_substring("Run command: #{joined}")
    end

    it 'raises CmdRunError when the command fails and exception is true' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/false')
        expect { cmd.close }.to raise_error(AutoHCK::CmdRunError, /Failed to run \(PID/)
        wait_for_log_substring('Run command:')
      end
    end

    it 'does not raise when exception is false even if exit status is non-zero' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/false', exception: false)
        expect(cmd.close.exitstatus).to eq(1)
      end
      wait_for_log_substring('finished with code 1')
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

    it 'drains all stdout before close returns' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/bash', '-c',
                      'for i in $(seq 1 50); do echo "line $i"; sleep 0.01; done; echo PASS: done')
        cmd.close

        expect(cmd.stddata['stdout']).to include('PASS: done')
        expect(cmd.stddata['stdout'].size).to be >= 51
      end
    end

    it 'captures output produced after the command process exits' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/sh', '-c',
                      "echo start; (sleep 0.25; echo 'PASS: done') & exit 0")
        expect(cmd.close.exitstatus).to be_zero
        expect(cmd.stddata['stdout']).to include('PASS: done')
      end
    end

    it 'returns the same status when close is called concurrently' do
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/true')
        statuses = Array.new(2) { Thread.new { cmd.close } }.map(&:value)
        expect(statuses.uniq.size).to eq(1)
      end
    end

    # bin/unix_spawn (used by the qemuhck pre-start commands to start swtpm and
    # virtiofsd) daemonizes a long-lived child which inherits CmdRun's pipes and
    # keeps them open after the command itself has exited. #close must not wait
    # for EOF on such pipes, otherwise it hangs and trips the 60s timeout that
    # guards QemuMachine#run_pre_start_commands.
    it 'does not block on pipes held open by a background process' do
      status = nil
      elapsed = nil
      AutoHCK::ResourceScope.open([]) do |scope|
        cmd = new_cmd(scope, '/bin/sh', '-c', 'sleep 60 &')
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = cmd.close
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        kill_process_group(cmd.pid)
      end
      expect(status.exitstatus).to be_zero
      expect(elapsed).to be < (described_class::PIPE_DRAIN_TIMEOUT + 5)
      wait_for_log_substring('finished with code 0')
    end
  end

  describe 'spawn options' do
    it 'passes chdir through to spawn' do
      Dir.mktmpdir('cmd_run_chdir') do |dir|
        AutoHCK::ResourceScope.open([]) do |scope|
          cmd = new_cmd(scope, '/bin/pwd', chdir: dir)
          cmd.close
        end
        wait_for_log_substring('stdout:')
        logged_dir = logger_io.string[/stdout: (.+?)(?:\n|$)/, 1]
        expect(File.realpath(logged_dir)).to eq(File.realpath(dir))
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
