# frozen_string_literal: true

require 'English'
require 'tempfile'

require_relative '../exceptions'

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
      @logger.info("Info dump:#{prep_log_stream(stdout)}") unless stdout.empty?
      return if stderr.empty?

      @logger.warn("Error dump:#{prep_log_stream(stderr)}")
    end

    def run_cmd(cmd)
      @logger.debug("Run command: #{cmd.join(' ')}")
      temp_file do |stdout|
        temp_file do |stderr|
          Process.wait(spawn(cmd.join(' '), out: stdout.path, err: stderr.path))
          log_stdout_stderr(stdout.read, stderr.read)
          e_message = "Failed to run: #{cmd.join(' ')}"
          raise CmdRunError, e_message unless $CHILD_STATUS.exitstatus.zero?
        end
      end
    end

    def run_cmd_no_fail(cmd)
      @logger.debug("Run command: #{cmd.join(' ')}")
      temp_file do |stdout|
        temp_file do |stderr|
          Process.wait(spawn(cmd.join(' '), out: stdout.path, err: stderr.path))
          log_stdout_stderr(stdout.read, stderr.read)
          @logger.debug("Command finished with code: #{$CHILD_STATUS.exitstatus}")
          $CHILD_STATUS.exitstatus
        end
      end
    end

    def file_gsub(src, dst, gsub_list)
      content = File.read(src)
      gsub_list.each do |k, v|
        content = content.gsub(k, v)
      end
      File.write(dst, content)
    end
  end
end
