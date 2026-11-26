# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # CmdRun class
  class CmdRun
    # Upper bound for draining stdout/stderr once the command has exited.
    #
    # Some commands daemonize a long-lived process (bin/unix_spawn starts
    # swtpm/virtiofsd) which inherits our pipes. Such a process keeps the write
    # ends open long after the command itself has exited, so waiting for EOF on
    # the pipes would block forever and trip the 60s timeout that guards
    # QemuMachine#run_pre_start_commands. Give the readers a bounded amount of
    # time to flush the output instead of hanging in #close. The output of an
    # exited command is already buffered in the pipe, so draining it is fast.
    PIPE_DRAIN_TIMEOUT = 2

    attr_reader :pid, :status, :stddata

    def initialize(scope, logger, *args, exception: true, **kwargs)
      @cmd = args.size == 1 ? args[0] : args.shelljoin
      @exception = exception
      @logger = logger
      @stddata = { 'stdout' => [], 'stderr' => [], 'both' => [] }
      @pipe_threads = []
      @pipe_threads_joined = false
      @error_raised = false
      @close_mutex = Mutex.new

      scope.transaction do |transaction|
        spawn_command(transaction, args, kwargs)
        log "Run command: #{@cmd}"
      end
    end

    def close
      @close_mutex.synchronize { close_locked }
    end

    private

    def close_locked
      if @status.nil?
        @status = Process.wait2(@pid)[1]
        log "Command finished with code #{@status.exitstatus}"
      end

      join_pipe_threads

      if @exception && !@status.exitstatus.zero? && !@error_raised
        e_message = "Failed to run (PID #{@pid}) (exit code #{@status.exitstatus}): #{@cmd}"
        @error_raised = true
        raise CmdRunError, e_message
      end

      @status
    end

    def log(message)
      @logger.info("CmdRun PID:#{@pid}") { message }
    end

    def join_pipe_threads
      return if @pipe_threads_joined

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PIPE_DRAIN_TIMEOUT
      undrained = @pipe_threads.reject do |thread|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        thread.join(remaining.positive? ? remaining : 0)
      end
      unless undrained.empty?
        log "#{undrained.size} output stream(s) are held open by a background process, " \
            'leaving the reader(s) to scope cleanup'
      end
      @pipe_threads_joined = true
    end

    def spawn_command(transaction, args, kwargs)
      ResourceScope.open do |tmp|
        out, out_reader = pipe(tmp, 'stdout')
        err, err_reader = pipe(tmp, 'stderr')
        @pid = spawn(*args, out:, err:, pgroup: 0, **kwargs)
        @pipe_threads = [out_reader, err_reader]
        transaction << ThreadScope.new(err_reader)
        transaction << ThreadScope.new(out_reader)
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
