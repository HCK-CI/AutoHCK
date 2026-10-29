# frozen_string_literal: true

module AutoHCK
  # Process exit codes of bin/auto_hck. They let callers tell a completed
  # run's verdict apart from a framework failure without parsing the result
  # artifacts (results.yaml / junit.xml / functest_results.json):
  #   0 - the run completed and passed, or nothing was run
  #       (query mode, diff checker skip)
  #   1 - the run aborted or was canceled: uncaught exception (framework
  #       error, generally retry-worthy) or AutoHCKInterrupt
  #   2 - the run completed but one or more tests failed (final verdict,
  #       not retry-worthy)
  EXIT_ERROR = 1
  EXIT_TEST_FAILED = 2

  def self.exit_code_for(status)
    case status
    when :failed then EXIT_TEST_FAILED
    when :error, :canceled then EXIT_ERROR
    else 0
    end
  end

  def self.run
    require 'bundler/setup'
    require 'dotenv/load'
    Bundler.require
    require_relative 'config/sentry'

    begin
      require_relative 'all'

      begin
        yield
      rescue AutoHCKInterrupt
        exit false
      end
    rescue StandardError => e
      Sentry.capture_exception(e)
      raise
    end
  end
end
