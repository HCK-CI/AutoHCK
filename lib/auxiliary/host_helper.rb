# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    def temp_file
      file = Tempfile.new('')
      yield(file)
    ensure
      file.close
      file.unlink
    end

    def prep_log_stream(stream)
      stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
    end

    def log_stdout_stderr(stdout, stderr)
      @logger.info('Info dump:' + prep_log_stream(stdout)) unless stdout.empty?
      return if stderr.empty?

      @logger.warn('Error dump:' + prep_log_stream(stderr))
    end

    def run_cmd(cmd)
      temp_file do |stdout|
        temp_file do |stderr|
          Process.wait(spawn(cmd.join(' '), out: stdout.path, err: stderr.path))
          log_stdout_stderr(stdout.read, stderr.read)
          e_message = "Failed to run: #{cmd.join(' ')}"
          raise CmdRunError, e_message unless $CHILD_STATUS.exitstatus.zero?
        end
      end
    end
  end
end
