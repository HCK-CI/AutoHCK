# frozen_string_literal: true

require_relative 'exceptions'

# AutoHCK module
module AutoHCK
  # Trap class
  class Trap
    class << self
      attr_writer :project
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
      raise AutoHCKInterrupt
    end

    @sig_timestamps = {}
    def self.normal_trap(signal)
      time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if time < @sig_timestamps[signal] + 1
        write_log("SIG#{signal}(2) received, aborting...")
        perform_trap(signal)
      else
        @sig_timestamps[signal] = time
        write_log("SIG#{signal}(1) received")
        write_log("Aborting if another SIG#{signal} is received in the span of the next one second")
      end
    end

    def self.ci_trap(signal)
      write_log("SIG#{signal}(1) received from CI, aborting ...")
      perform_trap(signal)
    end

    def self.init_traps(signals)
      @project = nil

      signals.each do |signal|
        @sig_timestamps[signal] = -Float::INFINITY
        Signal.trap(signal) { ENV['CI'].nil? ? normal_trap(signal) : ci_trap(signal) }
      end
    end
  end
end
