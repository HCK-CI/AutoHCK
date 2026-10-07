# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.3.0'

gem 'activesupport'
gem 'aws-sdk-s3'
gem 'csv'
gem 'dotenv'
gem 'dropbox_api'
gem 'erubi'
gem 'filelock'
gem 'httpclient'
gem 'mono_logger'
gem 'octokit'
gem 'openssl', require: false
gem 'rubyzip'
gem 'sentry-ruby'
gem 'sorbet-runtime'

# rtoolsHCK dependencies
gem 'winrm',      '= 2.3.9'
gem 'winrm-fs',   '= 1.3.5'

group :development, :test do
  gem 'sorbet', require: false
  gem 'tapioca', require: false
end

group :test do
  gem 'code-scanning-rubocop'
  gem 'rspec'
  gem 'rubocop'
end
