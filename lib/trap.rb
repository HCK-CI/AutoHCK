# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Trap class
  class Trap
    class << self
      attr_writer :project
    end

    def self.clean_threads
      Thread.list.each do |thread|
        thread.exit unless Thread.main.eql?(thread)
      end
    end

    def self.write_log(msg)
      if @project.nil? || @project.logger.nil?
        puts(msg)
      else
        @project.logger.warn(msg)
      end
    end

    def self.perform_trap(signal)
      Signal.trap(signal) do
        write_log("SIG#{signal}(*) received, ignoring...")
      end
      @project&.handle_cancel
      @project&.close
      clean_threads
      exit
    end

    @sig_status = {}
    def self.normal_trap(signal)
      if @sig_status[signal]
        write_log("SIG#{signal}(2) received, aborting...")
        perform_trap(signal)
      else
        @sig_status[signal] = true
        write_log("SIG#{signal}(1) received, aborting if another SIG#{signal} is"\
                            ' received in the span of the next one second')
        Thread.new do
          sleep 1
          @sig_status[signal] = false
        end
      end
    end

    def self.ci_trap(signal)
      @sig_status[signal] = true
      write_log("SIG#{signal}(1) received from CI, aborting ...")
      perform_trap(signal)
    end

    def self.init_traps(signals)
      @project = nil

      signals.each do |signal|
        @sig_status[signal] = false
        Signal.trap(signal) { ENV['CI'].nil? ? normal_trap(signal) : ci_trap(signal) }
      end
    end
  end
end
