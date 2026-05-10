# frozen_string_literal: true

require 'shellwords'
require_relative '../../../lib/all'

# rubocop:disable Metrics/BlockLength
describe AutoHCK::QemuMachine::Runner do
  describe 'abort / retry constants' do
    it 'documents soft abort retry count' do
      expect(described_class::SOFT_ABORT_RETRIES).to eq(3)
    end

    it 'documents abort polling interval in seconds' do
      expect(described_class::ABORT_SLEEP).to eq(30)
    end
  end

  describe '#check_fails_too_quickly' do
    let(:runner) { described_class.allocate }

    it 'returns false when status is zero' do
      expect(runner.send(:check_fails_too_quickly, 0)).to be(false)
    end

    it 'returns false on the first non-zero exit' do
      expect(runner.send(:check_fails_too_quickly, 1)).to be(false)
    end

    it 'returns true on a second non-zero exit within the window' do
      runner.send(:check_fails_too_quickly, 1)
      expect(runner.send(:check_fails_too_quickly, 2)).to be(true)
    end

    it 'resets the window after a successful zero exit' do
      runner.send(:check_fails_too_quickly, 1)
      expect(runner.send(:check_fails_too_quickly, 0)).to be(false)
      expect(runner.send(:check_fails_too_quickly, 1)).to be(false)
    end

    it 'treats nil status like a failure for the rapid-fail detector' do
      expect(runner.send(:check_fails_too_quickly, nil)).to be(false)
      expect(runner.send(:check_fails_too_quickly, nil)).to be(true)
    end
  end

  describe 'Linux process primitives used by Runner cleanup', :linux_process do
    it 'waits on a real /bin/true child with exit status zero' do
      pid = spawn('/bin/true', out: File::NULL, err: File::NULL)
      _pid, status = Process.wait2(pid)
      expect(status.exitstatus).to be_zero
    end

    it 'captures a non-zero exit from /bin/false' do
      pid = spawn('/bin/false', out: File::NULL, err: File::NULL)
      _pid, status = Process.wait2(pid)
      expect(status.exitstatus).to eq(1)
    end

    it 'terminates a stuck child with SIGKILL like the QEMU fallback path' do
      pid = spawn('sleep', '120', out: File::NULL, err: File::NULL)
      expect { Process.kill(0, pid) }.not_to raise_error

      Process.kill('KILL', pid)
      _pid, status = Process.wait2(pid)

      expect(status.signaled?).to be(true)
      expect(status.termsig).to eq(Signal.list.fetch('KILL'))
    end

    it 'runs qemu-system-x86_64 --version when the binary is on PATH' do
      qemu = `command -v qemu-system-x86_64 2>/dev/null`.strip
      skip 'qemu-system-x86_64 not in PATH' if qemu.empty?

      out = `#{Shellwords.shelljoin([qemu, '--version'])} 2>&1`
      expect(out).to match(/qemu/i)
    end

    it 'runs qemu-kvm --version when the binary is on PATH' do
      qemu = `command -v qemu-kvm 2>/dev/null`.strip
      skip 'qemu-kvm not in PATH' if qemu.empty?

      out = `#{Shellwords.shelljoin([qemu, '--version'])} 2>&1`
      expect(out).to match(/qemu/i)
    end
  end
end
# rubocop:enable Metrics/BlockLength
