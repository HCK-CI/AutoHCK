# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # CmdRun class
  class CmdRun
    attr_reader :pid, :status, :stddata

    def initialize(scope, logger, *args, exception: true, **kwargs)
      @cmd = args.size == 1 ? args[0] : args.shelljoin
      @exception = exception
      @logger = logger
      @stddata = { 'stdout' => [], 'stderr' => [], 'both' => [] }

      scope.transaction do |transaction|
        spawn_command(transaction, args, kwargs)
        log "Run command: #{@cmd}"
      end
    end

    def close
      if @status.nil?
        @status = Process.wait2(@pid)[1]
        e_message = "Failed to run (PID #{@pid}) (exit code #{@status.exitstatus}): #{@cmd}"
        raise CmdRunError, e_message if @exception && !@status.exitstatus.zero?

        log "Command finished with code #{@status.exitstatus}"
      end

      @status
    end

    private

    def log(message)
      @logger.info("CmdRun PID:#{@pid}") { message }
    end

    def spawn_command(transaction, args, kwargs)
      ResourceScope.open do |tmp|
        out, th1 = pipe(tmp, 'stdout')
        err, th2 = pipe(tmp, 'stderr')
        @pid = spawn(*args, out:, err:, pgroup: 0, **kwargs)
        transaction << ThreadScope.new(th2)
        transaction << ThreadScope.new(th1)
        transaction << self
      end
    end

    def pipe(scope, name)
      read, write = IO.pipe
      scope << write

      thread = Thread.new do
        read.each(chomp: true) do |data|
          log "#{name}: #{data}".encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
          @stddata[name] << data
          @stddata['both'] << data
        end
      ensure
        read.close
      end

      [write, thread]
    end
  end
end
