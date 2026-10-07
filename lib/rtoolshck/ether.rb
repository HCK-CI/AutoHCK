# frozen_string_literal: true

require_relative 'exceptions'
require_relative 'server'

module AutoHCK
  # ether class
  class Ether
    # ether buffer size
    ETHER_BUFFER_SIZE = 1024
    # ether exit timeout
    ETHER_EXIT_TIMEOUT = 5

    def initialize(init_opts)
      @log_to_stdout = init_opts[:log_to_stdout]
      @stdout_logger = Logger.new($stdout) if @log_to_stdout
      @logger = init_opts[:logger]
      load_instance_variables(init_opts)
      load_server
      logger('debug', 'ether/initialize') { "to #{@server_addr}:#{@server_port}" }
      load_ether
    rescue StandardError
      close
      raise
    end

    private

    def get_exception_stack(exception)
      exception.backtrace.select { |line| line.include?(File.dirname(__FILE__)) }
               .join("\n   -- ")
    end

    def log_exception(exception, level)
      eclass = exception.class
      emessage = exception.message
      estack = get_exception_stack(exception)
      if exception.is_a?(RToolsHCKError)
        ewhere = exception.where
        logger(level, ewhere) { "(#{eclass}) #{emessage}\n   -- #{estack}" }
      else
        logger(level, eclass) { "#{emessage}\n   -- #{estack}" }
      end
    end

    def logger(level, progname = nil, &)
      @stdout_logger.public_send(level, progname, &) if @log_to_stdout
      @logger&.public_send(level, progname, &)
    end

    def load_instance_variables(init_opts)
      @winrm_connection_options = init_opts[:winrm_connection_options]
      @server_addr = init_opts[:server_addr]
      @server_port = init_opts[:server_port]
      @outp_dir = init_opts[:outp_dir]
      @operation_timeout = init_opts[:operation_timeout]
      @connection_timeout = init_opts[:connection_timeout]
      @r_script_file = init_opts[:r_script_file]
    end

    def server_init_opts
      {
        winrm_connection_options: @winrm_connection_options,
        server_port: @server_port,
        connection_timeout: @connection_timeout,
        outp_dir: @outp_dir,
        r_script_file: @r_script_file,
        log_to_stdout: @log_to_stdout,
        logger: @logger
      }
    end

    def load_server
      logger('debug', 'ether/load_server') { "server #{@toolshck_server.nil? ? 'is not' : 'already'} initialized" }
      @toolshck_server ||= Server.new(server_init_opts)
      @toolshck_server.run_server
    end

    def load_ether
      logger('debug', 'ether/load_ether') { 'waiting for client acceptance' }
      wait_for_client_acceptance
      logger('info', 'ether/load_ether') { 'connected' }
      @loaded = true
    end

    def wait_for_client_acceptance
      @ether = connect

      unless fetch_output_with_timeout(@connection_timeout).eql?('START')
        e_message = 'something went wrong, didn\'t receive (START)'
        raise EtherError.new('ether/wait_for_client_acceptance'), e_message
      end
    rescue StandardError
      e_message = 'waiting for the client acceptance timed out'
      raise EtherError.new('ether/wait_for_client_acceptance'), e_message
    end

    def connect
      Timeout.timeout(@connection_timeout) do
        TCPSocket.new(@server_addr, @server_port)
      rescue Errno::ECONNREFUSED
        sleep(1)
        retry
      end
    end

    def fetch_output_with_timeout(timeout)
      Timeout.timeout(timeout) do
        until @ether.ready?; end

        length = @ether.readline.rstrip.to_i

        fetch(length)
      end
    rescue IO::WaitReadable, Errno::ECONNRESET, EOFError, Errno::EPIPE => e
      raise EtherError.new('ether'), "[#{e.class}] #{e.message}", e.backtrace
    end

    def fetch(length)
      data = ''
      while data.length != length
        until @ether.ready?; end

        read_length = [ETHER_BUFFER_SIZE, length - data.length].min
        data += @ether.read_nonblock(read_length)
      end
      data
    end

    def unload_server
      @loaded = false
      @toolshck_server&.close
    rescue StandardError => e
      log_exception(e, 'warn')
    end

    public

    def close
      logger('debug', 'ether/close') { 'closing ether' }
      if @ether && !cmd('exit', ETHER_EXIT_TIMEOUT).eql?('END')
        e_message = 'closing failed'
        raise EtherError.new('ether/close'), e_message
      end
    ensure
      logger('debug', 'ether/close') { 'closed' }
      @ether&.close
      unload_server
    end

    def cmd(cmd, timeout = @operation_timeout)
      unless @loaded
        load_server
        load_ether
      end

      flush

      @ether.puts(cmd)

      fetch_output_with_timeout(timeout)
    rescue StandardError => e
      unload_server

      raise EtherError.new('ether/cmd'), "cmd (#{cmd}) failed with error #{e.message}"
    end

    private

    def flush
      flushed = ''
      loop { flushed += @ether.read_nonblock(ETHER_BUFFER_SIZE) }
    rescue IO::WaitReadable, Errno::ECONNRESET, EOFError, Errno::EPIPE
      return if flushed.empty?

      logger('debug', 'ether/flush') { "flushed data:\n#{flushed}" }
    end
  end
end
