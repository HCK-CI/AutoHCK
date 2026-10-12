# frozen_string_literal: true

require 'base64'
require 'fileutils'

module AutoHCK
  # File manager backed by SSH/SFTP, mirroring WinRM::FS::FileManager.
  class SshFileManager
    UNITS = %w[B KiB MiB GiB TiB].freeze
    SSH_TRANSPORT_ERRORS = [
      Net::SSH::Exception,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT,
      Errno::ECONNRESET,
      IOError
    ].freeze

    def initialize(opts)
      @addr = opts.fetch(:addr)
      @user = opts.fetch(:user)
      @pass = opts.fetch(:pass)
      @port = opts.fetch(:port)
      @timeout = opts.fetch(:timeout)
      @logger_proc = opts.fetch(:logger_proc)
      @mutex = Mutex.new
      @last_percent = 0
      @transfer_total = 0
      @transfer_now = 0
    end

    def upload(local_path, remote_path, &)
      @mutex.synchronize do
        local_path = local_path.to_s
        remote_path = expand_guest_path(normalize_path(remote_path))
        reset_progress

        if File.directory?(local_path)
          upload_directory(local_path, remote_path, &)
        else
          upload_file(local_path, remote_path, &)
        end
      end
    end

    def download(remote_path, local_path, &)
      @mutex.synchronize do
        remote_path = expand_guest_path(normalize_path(remote_path))
        local_path = local_path.to_s
        reset_progress

        with_sftp do |sftp|
          if sftp_directory?(sftp, remote_path)
            download_directory(sftp, remote_path, local_path, &)
          else
            download_file(sftp, remote_path, local_path, &)
          end
        end

        local_path
      end
    end

    # false only when Test-Path completes and reports the path is absent.
    # Transport failures surface as RToolsHCKError (raised by with_ssh) so callers
    # retry instead of mistaking a connection drop for an absent file.
    def exists?(path)
      @mutex.synchronize { remote_path_exists?(normalize_path(path)) }
    end

    def delete(path)
      @mutex.synchronize { delete_remote_path(normalize_path(path)) }
    end

    def temp_dir
      @mutex.synchronize do
        @temp_dir ||= begin
          # Prefer cmd.exe to avoid PowerShell CLIXML noise on stdout.
          stdout, exitcode = run_ssh_command('cmd.exe /c echo %TEMP%')
          path = extract_windows_path(stdout)
          unless exitcode.zero? && path
            raise RToolsHCKError.new('ssh_fs/temp_dir'), "failed to read TEMP: #{stdout.inspect}"
          end

          path
        end
      end
    end

    def close
      @mutex.synchronize { close_ssh }
    end

    private

    def logger(level, progname = nil, &)
      @logger_proc&.call(level, progname, &)
    end

    def normalize_path(path)
      path.to_s.tr('\\', '/')
    end

    # Windows OpenSSH SFTP expects absolute paths like /C:/Windows/Temp/...
    def sftp_path(path)
      path = normalize_path(path)
      return path if path.start_with?('/')

      "/#{path}"
    end

    def extract_windows_path(stdout)
      stdout.to_s.lines.map(&:strip).find { |line| line.match?(%r{\A[A-Za-z]:[/\\]}) }
            &.tr('\\', '/')
    end

    def ps_escape(value)
      value.to_s.gsub("'", "''")
    end

    def remote_path_exists?(path)
      stdout, exitcode = powershell(test_path_script(path))
      return true if exitcode.zero?
      return false if exitcode == 1

      raise RToolsHCKError.new('ssh_fs/exists?'), command_failure_message("Test-Path failed for #{path}", stdout)
    end

    def test_path_script(path)
      'try { ' \
        "#{ps_expand_assignment(path)}" \
        'if (Test-Path -LiteralPath $path) { exit 0 } else { exit 1 } ' \
        '} catch { Write-Output $_.Exception.Message; exit 2 }'
    end

    def delete_remote_path(path)
      stdout, exitcode = powershell(delete_script(path))
      return true if exitcode.zero?

      raise RToolsHCKError.new('ssh_fs/delete'), command_failure_message("failed to delete #{path}", stdout)
    end

    # Missing paths are success so deploy can delete-then-upload. A locked or
    # inaccessible target must fail the command instead of reporting success.
    def delete_script(path)
      'try { ' \
        "#{ps_expand_assignment(path)}" \
        'if (Test-Path -LiteralPath $path) { ' \
        'Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }; ' \
        'exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }'
    end

    # ${env:SystemRoot} and similar guest paths must be expanded before SFTP,
    # which has no PowerShell provider. Plain paths skip the extra exec.
    def expand_guest_path(path)
      return path unless path.include?('$')

      stdout, exitcode = powershell(expand_path_script(path))
      resolved = extract_windows_path(stdout)
      return resolved if exitcode.zero? && resolved

      raise RToolsHCKError.new('ssh_fs/path'),
            command_failure_message("failed to resolve #{path}", stdout)
    end

    def expand_path_script(path)
      'try { ' \
        "#{ps_expand_assignment(path)}" \
        'Write-Output $path; exit 0 ' \
        '} catch { Write-Output $_.Exception.Message; exit 1 }'
    end

    def ps_expand_assignment(path)
      "$raw = '#{ps_escape(path)}'; " \
        '$path = $ExecutionContext.InvokeCommand.ExpandString($raw); '
    end

    def command_failure_message(prefix, stdout)
      detail = stdout.to_s.strip
      return prefix if detail.empty?

      "#{prefix}: #{detail}"
    end

    def reset_progress
      @last_percent = 0
      @transfer_total = 0
      @transfer_now = 0
    end

    def size_to_str(number)
      if number.to_i < 1024
        exponent = 0
      else
        max_exp = UNITS.size - 1
        exponent = (Math.log(number) / Math.log(1024)).to_i
        exponent = max_exp if exponent > max_exp
        number /= 1024.0**exponent
      end

      "#{number.round(2)} #{UNITS[exponent]}"
    end

    def log_progress(total, now)
      return if total.to_i.zero?

      percent = Integer(100 * now / total)
      return if percent - @last_percent < 5 && (percent != 100 || @last_percent == 100)

      logger('info', 'ssh_fs/transfer') { "Transferred #{size_to_str(now)} (#{percent}%)" }
      @last_percent = percent
    end

    def ssh_options
      {
        password: @pass,
        port: @port,
        timeout: @timeout,
        non_interactive: true,
        # Guest images are regenerated, so host keys are not stable and there is
        # no known_hosts file to check. Skipping verification is expected.
        verify_host_key: :never,
        auth_methods: %w[password],
        number_of_password_prompts: 0,
        append_all_supported_algorithms: true,
        keepalive: true,
        keepalive_interval: 30
      }
    end

    def close_ssh
      @ssh&.close
    rescue StandardError
      nil
    ensure
      @ssh = nil
    end

    def with_ssh
      open_ssh_session
      yield @ssh
    rescue *SSH_TRANSPORT_ERRORS
      close_ssh
      reconnect_ssh { yield @ssh }
    end

    # One SFTP session per transfer, including a whole directory tree. Exec
    # channels stay on the separate persistent @ssh connection; mixing them onto
    # the SFTP session hangs. The two connections coexist, so the exec session is
    # left open here and reused across transfers instead of reconnecting each time.
    def with_sftp(&)
      Net::SFTP.start(@addr, @user, ssh_options, &)
    rescue *SSH_TRANSPORT_ERRORS => e
      raise_transport_error('ssh_fs/sftp', e)
    end

    def open_ssh_session
      return if @ssh && !@ssh.closed?

      @ssh = Net::SSH.start(@addr, @user, ssh_options)
    end

    def reconnect_ssh
      open_ssh_session
      yield
    rescue *SSH_TRANSPORT_ERRORS => e
      close_ssh
      raise_transport_error('ssh_fs/ssh', e)
    end

    def raise_transport_error(where, error)
      raise RToolsHCKError.new(where), "SSH connection failed: #{error.class}: #{error.message}"
    end

    def completed_command_result(stdout, exitcode)
      return [stdout, exitcode] unless exitcode.nil?

      message = command_failure_message('SSH command ended without an exit status', stdout)
      raise RToolsHCKError.new('ssh_fs/powershell'), message
    end

    def powershell(script)
      wrapped = "$ProgressPreference='SilentlyContinue'; #{script}"
      encoded = Base64.strict_encode64(wrapped.encode('UTF-16LE'))
      command = "powershell.exe -NoProfile -NonInteractive -EncodedCommand #{encoded}"
      run_ssh_command(command)
    end

    def run_ssh_command(command)
      stdout = String.new
      exitcode = nil

      with_ssh do |ssh|
        # with_ssh may re-yield this block after a reconnect; start each attempt
        # from a clean buffer so failed-attempt output is not parsed as the result.
        stdout.clear
        exitcode = nil
        ssh.open_channel do |channel|
          channel.exec(command) do |ch, success|
            raise RToolsHCKError.new('ssh_fs/powershell'), 'exec failed' unless success

            collect_channel_output(ch, stdout) { |code| exitcode = code }
          end
        end
        ssh.loop
      end

      completed_command_result(stdout, exitcode)
    end

    def collect_channel_output(channel, stdout)
      channel.on_data { |_, data| stdout << data }
      channel.on_extended_data { |_, _, data| stdout << data }
      channel.on_request('exit-status') { |_, data| yield data.read_long }
    end

    def ensure_remote_directory(path)
      path = normalize_path(path)
      return if path.nil? || path.empty? || path.match?(%r{\A[A-Za-z]:/?\z})

      stdout, exitcode = powershell(
        'try { ' \
        "New-Item -ItemType Directory -Force -Path '#{ps_escape(path)}' " \
        '-ErrorAction Stop | Out-Null; exit 0 ' \
        '} catch { Write-Output $_.Exception.Message; exit 1 }'
      )
      return if exitcode.zero?

      raise RToolsHCKError.new('ssh_fs/mkdir'),
            command_failure_message("failed to create directory #{path}", stdout)
    end

    def remote_dirname(path)
      path = normalize_path(path)
      path.sub(%r{/[^/]*\z}, '')
    end

    def upload_directory(local_path, remote_path, &)
      ensure_remote_directory(remote_path)
      entries = Dir.children(local_path)
      logger('info', 'ssh_fs/transfer') do
        "Uploading directory #{local_path} -> #{remote_path} (#{entries.size} entries)"
      end

      with_sftp do |sftp|
        entries.each do |entry|
          local_entry = File.join(local_path, entry)
          remote_entry = "#{remote_path}/#{entry}"
          if File.directory?(local_entry)
            upload_directory_via_sftp(sftp, local_entry, remote_entry, &)
          else
            sftp_upload_file(sftp, local_entry, remote_entry, &)
          end
        end
      end
    end

    def upload_directory_via_sftp(sftp, local_path, remote_path, &)
      ensure_remote_directory(remote_path)
      Dir.children(local_path).each do |entry|
        local_entry = File.join(local_path, entry)
        remote_entry = "#{remote_path}/#{entry}"
        if File.directory?(local_entry)
          upload_directory_via_sftp(sftp, local_entry, remote_entry, &)
        else
          sftp_upload_file(sftp, local_entry, remote_entry, &)
        end
      end
    end

    def upload_file(local_path, remote_path, &)
      ensure_remote_directory(remote_dirname(remote_path))
      with_sftp { |sftp| sftp_upload_file(sftp, local_path, remote_path, &) }
    end

    def sftp_upload_file(sftp, local_path, remote_path, &block)
      remote = sftp_path(remote_path)
      reset_progress
      logger('info', 'ssh_fs/transfer') do
        "Uploading #{File.basename(local_path)} (#{size_to_str(File.size(local_path))})"
      end

      sftp.upload!(local_path, remote) do |event, _uploader, *args|
        handle_sftp_progress(event, args, local_path, remote_path, &block)
      end
    rescue Net::SFTP::StatusException => e
      raise RToolsHCKError.new('ssh_fs/upload'),
            "SFTP upload failed #{local_path} -> #{remote_path}: #{e.message}"
    end

    def sftp_directory?(sftp, path)
      directory_attribute?(sftp.stat!(sftp_path(path)))
    rescue Net::SFTP::StatusException => e
      return false if e.code == Net::SFTP::Constants::StatusCodes::FX_NO_SUCH_FILE

      raise RToolsHCKError.new('ssh_fs/stat'), "SFTP stat failed for #{path}: #{e.message}"
    end

    def directory_attribute?(attrs)
      return false if attrs.permissions.nil?

      attrs.directory? == true
    end

    def download_directory(sftp, remote_path, local_path, &)
      FileUtils.mkdir_p(local_path)
      logger('info', 'ssh_fs/transfer') { "Downloading directory #{remote_path} -> #{local_path}" }
      sftp_download(sftp, remote_path, local_path, recursive: true, &)
    end

    def download_file(sftp, remote_path, local_path, &)
      FileUtils.mkdir_p(File.dirname(local_path))
      logger('info', 'ssh_fs/transfer') { "Downloading #{remote_path}" }
      sftp_download(sftp, remote_path, local_path, &)
    end

    def sftp_download(sftp, remote_path, local_path, recursive: false, &block)
      options = {}
      options[:recursive] = true if recursive
      sftp.download!(sftp_path(remote_path), local_path, options) do |event, _downloader, *args|
        handle_sftp_progress(event, args, local_path, remote_path, &block)
      end
    rescue Net::SFTP::StatusException => e
      raise RToolsHCKError.new('ssh_fs/download'),
            "SFTP download failed #{remote_path} -> #{local_path}: #{e.message}"
    end

    def handle_sftp_progress(event, args, local_path, remote_path)
      case event
      when :open
        file = args[0]
        @transfer_total = file.size.to_i
        @transfer_now = 0
        @last_percent = 0
      when :put, :get
        @transfer_now = [args[1].to_i + args[2].to_s.bytesize, @transfer_total].min
        log_progress(@transfer_total, @transfer_now)
        yield(@transfer_now, @transfer_total, local_path, remote_path) if block_given?
      when :finish
        log_progress(@transfer_total, @transfer_total) if @transfer_total.positive?
      end
    end
  end
end
