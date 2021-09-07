# frozen_string_literal: true

require 'sentry-ruby'
require './lib/version'
require 'mono_logger'

# AutoHCK module
module AutoHCK
  Sentry.init do |config|
    config.release = AutoHCK::VERSION

    # Send events synchronously.
    config.background_worker_threads = 0

    # Sentry uses breadcrumbs to create a trail of
    # events that happened prior to an issue.
    config.breadcrumbs_logger = [:sentry_logger]

    config.before_breadcrumb = lambda do |breadcrumb, _hint|
      if breadcrumb.level.to_s.downcase == 'debug'
        nil
      else
        breadcrumb
      end
    end

    # The maximum number of breadcrumbs the SDK would hold.
    config.max_breadcrumbs = 2_500

    # Set traces_sample_rate to 1.0 to capture 100%
    # of transactions for performance monitoring.
    config.traces_sample_rate = 1.0

    unless ENV['SENTRY_TRANSPORT_SSL_CA'].nil?
      if File.exist?(ENV['SENTRY_TRANSPORT_SSL_CA'])
        config.transport.ssl_ca_file = ENV['SENTRY_TRANSPORT_SSL_CA']
      else
        MonoLogger.new($stdout).warn('SENTRY_TRANSPORT_SSL_CA environment specified, but file does not exist')
      end
    end
  end
end
