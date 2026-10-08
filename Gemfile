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
# json 3.0 rejects the positional options hash that multi_json still passes to JSON.parse.
gem 'json', '~> 2.21'
gem 'mono_logger'
gem 'octokit'
gem 'openssl', require: false
gem 'rtoolsHCK', git: 'https://github.com/HCK-CI/rtoolsHCK.git', ref: 'v0.7.3'
gem 'rubyzip'
gem 'sentry-ruby'
gem 'sorbet-runtime'

group :development, :test do
  gem 'sorbet', require: false
  gem 'tapioca', require: false
end

group :test do
  gem 'code-scanning-rubocop'
  gem 'rspec'
  gem 'rubocop'
end
