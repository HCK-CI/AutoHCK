# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.1.0'

gem 'activesupport'
gem 'csv'
gem 'curb'
gem 'dotenv'
gem 'dropbox_api'
gem 'filelock'
gem 'mono_logger'
gem 'octokit'
gem 'openssl', require: false
gem 'rtoolsHCK', git: 'https://github.com/HCK-CI/rtoolsHCK.git', tag: 'v0.4.3'
gem 'rubyzip'
gem 'sentry-ruby'
gem 'sorbet-runtime'
gem 'sys-cpu'

group :development, :test do
  gem 'sorbet', require: false
  gem 'tapioca', require: false
end

group :test do
  gem 'code-scanning-rubocop'
  gem 'rspec'
  gem 'rubocop'
end
