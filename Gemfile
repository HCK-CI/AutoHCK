# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.3.0'

gem 'activesupport'
gem 'aws-sdk-s3'
gem 'csv'
gem 'curb'
gem 'dotenv'
gem 'dropbox_api'
gem 'openssl', require: false
gem 'filelock'
gem 'httpclient'
gem 'octokit'
gem 'mono_logger'
gem 'rtoolsHCK', git: 'https://github.com/HCK-CI/rtoolsHCK.git', tag: 'v0.5.3'
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
