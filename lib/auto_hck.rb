# frozen_string_literal: true

module AutoHCK
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
