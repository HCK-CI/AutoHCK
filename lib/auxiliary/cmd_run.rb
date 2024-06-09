# frozen_string_literal: true

require 'shellwords'
require 'tempfile'
require_relative 'resource_scope'

# AutoHCK module
module AutoHCK
  # CmdRun class
  class CmdRun
    attr_reader :pid, :status

    def initialize(scope, logger, *args, exception: true, **kwargs)
      @cmd = args.size == 1 ? args[0] : args.shelljoin
      @exception = exception
      @logger = logger

      scope.transaction do |transaction|
        ResourceScope.open do |tmp|
          out = pipe(tmp, 'stdout')
          err = pipe(tmp, 'stderr')
          @pid = spawn(*args, out:, err:, pgroup: 0, **kwargs)
          transaction << self
        end

        log "Run command: #{@cmd}"
      end
    end

    def close
      if @status.nil?
        @status = Process.wait2(@pid)[1]
        e_message = "Failed to run (PID #{@pid}): #{@cmd}"
        raise CmdRunError, e_message if @exception && !@status.exitstatus.zero?

        log "Command finished with code #{@status.exitstatus}"
      end

      @status
    end

    private

    def log(message)
      @logger.info("CmdRun PID:#{@pid}") { message }
    end

    def pipe(scope, name)
      read, write = IO.pipe
      scope << write

      Thread.new do
        read.each(chomp: true) { log "#{name}: #{_1}" }
      ensure
        read.close
      end

      write
    end
  end
end
