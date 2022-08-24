# frozen_string_literal: true

require 'tempfile'

# AutoHCK module
module AutoHCK
  # CmdRun class
  class CmdRun
    attr_reader :pid

    def initialize(logger, cmd)
      @cmd = cmd.join(' ')
      logger.info("Run command: #{@cmd}")
      @logger = logger
      @stdout = Tempfile.new
      @stdout.unlink
      @stderr = Tempfile.new
      @stderr.unlink
      @pid = spawn(@cmd, out: @stdout, err: @stderr)
    end

    def wait(flags = 0)
      wait_for_status(flags) do
        e_message = "Failed to run: #{@cmd}"
        raise CmdRunError, e_message unless _1.exitstatus.zero?
      end
    end

    def wait_no_fail(flags = 0)
      wait_for_status(flags) do
        @logger.info("Command finished with code: #{_1.exitstatus}")
      end
    end

    private

    def prep_log_stream(stream)
      stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
    end

    def wait_for_status(flags)
      _, status = Process.wait2(@pid, flags)
      return if status.nil?

      begin
        begin
          @stdout.rewind
          stdout = @stdout.read
        ensure
          @stdout.close
        end

        @stderr.rewind
        stderr = @stderr.read
      ensure
        @stderr.close
      end

      @logger.info("Info dump:#{prep_log_stream(stdout)}") unless stdout.empty?
      @logger.warn("Error dump:#{prep_log_stream(stderr)}") unless stderr.empty?

      yield status

      status
    end
  end
end
