# frozen_string_literal: true

require_relative 'exceptions'

module AutoHCK
  # server class
  class Server
    def initialize(init_opts)
      @log_to_stdout = init_opts[:log_to_stdout]
      @stdout_logger = Logger.new($stdout) if @log_to_stdout
      @logger = init_opts[:logger]
      load_instance_variables(init_opts)
      logger('debug', 'server/initialize') { "on port #{@server_port}" }
    end

    def run_server
      logger('info', 'server/run_server') { "on port #{@server_port}" }

      connection = WinRM::Connection.new(@winrm_connection_options)

      @winrm_ps = connection.shell(:powershell)
      @winrm_fs = WinRM::FS::FileManager.new(connection)

      check_script_file
      load_toolshck_server
    end

    private

    def logger(level, progname = nil, &)
      @stdout_logger.public_send(level, progname, &) if @log_to_stdout
      @logger&.public_send(level, progname, &)
    end

    def load_instance_variables(init_opts)
      @winrm_connection_options = init_opts[:winrm_connection_options]
      @server_port = init_opts[:server_port]
      @connection_timeout = init_opts[:connection_timeout]
      @outp_dir = init_opts[:outp_dir]
      @r_script_file = init_opts[:r_script_file]
    end

    def check_script_file
      logger('debug', 'server/check_script_file') { 'checking script file on remote' }
      deploy_script_file
      unless @winrm_fs.exists?(@r_script_file)
        raise ServerError.new('server/check_script_file'),
              'toolsHCK.ps1 script was not found on remote.'
      end
      logger('info', 'server/check_script_file') { 'checked' }
    end

    def deploy_script_file
      tools_hck = File.expand_path('../rtoolshck/toolsHCK.ps1', __dir__)
      logger('debug', 'server/deploy_script_file') { 'deploying script file on remote' }
      @winrm_fs.delete(@r_script_file)
      @winrm_fs.upload(tools_hck, @r_script_file)
      logger('debug', 'server/deploy_script_file') { 'deployed' }
    end

    def start_server_with_log_fetcher
      log_l_path = "#{@outp_dir}/#{Time.now.strftime('%d-%m-%Y_%H_%M_%S')}_toolsHCK.log"
      File.open(log_l_path, 'a') do |file|
        @winrm_ps.send_pipeline_command(process_script) do |message|
          if message.parsed_data.respond_to?(:output)
            file.print message.parsed_data.output
          else
            file.print message.parsed_data.raw
          end
        end
      end
    end

    def load_toolshck_server
      logger('debug', 'server/load_toolshck_server') do
        "loading server to listen on port #{@server_port}"
      end
      @log_fetcher = Thread.new do
        start_server_with_log_fetcher
      rescue WinRM::WinRMError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE => e
        # Safe to ignore as the most likely cause is that the pipeline was closed
        # before we finished fetching all messages and we don't want to crash the server
        # in that case. This can happen when the server is stopped while we're still fetching messages.
        # WinRMError can be raised instead of Errno::EPIPE when the WinRM connection is closed while we're
        # still fetching messages, so we need to catch both.
        # In any case, Ether will restart the server before the next command execution,
        # so we won't be left with a hanging thread
        logger('warn', 'server/log_fetcher') { "failed to fetch log message: #{e.message}" }
      end
      logger('info', 'server/load_toolshck_server') { 'loaded' }
    end

    def process_script
      'powershell -ExecutionPolicy Bypass -File ' \
        "#{@r_script_file} -server -timeout #{@connection_timeout} -port " \
        "#{@server_port}"
    end

    def guest_basename(path)
      path&.split('\\')&.last
    end

    public

    def close
      logger('debug', 'server/close') { 'closing server' }
      @log_fetcher&.kill
    ensure
      logger('info', 'server/close') { 'closed' }
      @winrm_ps&.close
    end
  end
end
