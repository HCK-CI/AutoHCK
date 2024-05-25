# frozen_string_literal: true

require 'shellwords'
require 'tempfile'
require_relative 'resource_scope'

# AutoHCK module
module AutoHCK
  # CmdRun class
  class CmdRun
    attr_reader :pid

    def initialize(logger, *args, **kwargs)
      @cmd = args.size == 1 ? args : args.shelljoin
      @logger = logger
      @stdout = Tempfile.new
      @stdout.unlink
      @stderr = Tempfile.new
      @stderr.unlink
      @pid = spawn(*args, out: @stdout, err: @stderr, pgroup: 0, **kwargs)
      logger.info("Run command (PID #{@pid}): #{@cmd}")
    end

    def wait(flags = 0)
      wait_for_status(flags) do |status|
        e_message = "Failed to run (PID #{@pid}): #{@cmd}"
        raise CmdRunError, e_message unless status.exitstatus.zero?
      end
    end

    def wait_no_fail(flags = 0)
      wait_for_status(flags) do |status|
        @logger.info("Command finished with code (PID #{@pid}): #{status.exitstatus}")
      end
    end

    private

    def prep_log_stream(stream)
      stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
    end

    def wait_for_status(flags)
      _, status = Process.wait2(@pid, flags)
      return if status.nil?

      ResourceScope.open do |scope|
        scope << @stdout
        scope << @stderr

        @stdout.rewind
        stdout = @stdout.read
        @stderr.rewind
        stderr = @stderr.read

        @logger.info("Info dump (PID #{@pid}):#{prep_log_stream(stdout)}") unless stdout.empty?
        @logger.warn("Error dump (PID #{@pid}):#{prep_log_stream(stderr)}") unless stderr.empty?
      end

      yield status

      status
    end
  end
end
