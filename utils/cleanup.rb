# frozen_string_literal: true

require 'optparse'
require 'json'
require 'fileutils'
require 'time'

VERSION = '0.0.1'
MONTH_IN_SECS = 2_592_000
CONFIG_JSON = 'config.json'

def read_json(json_file)
  JSON.parse(File.read(json_file))
rescue Errno::ENOENT, JSON::ParserError
  puts "Could not open #{json_file} file"
  exit(1)
end

def delete?(timestamp)
  test_time = Time.strptime(timestamp, '%Y_%m_%d_%H_%M_%S')
  Time.now - test_time > MONTH_IN_SECS
end

def delete(test_run)
  puts "Deleting #{test_run}"
  FileUtils.remove_entry_secure(test_run, true)
end

def cleanup
  config = read_json(CONFIG_JSON)
  workspace_path = config['workspace_path']
  test_runs = Dir["#{workspace_path}/*/*/*/*"]
  test_runs.each do |test_run|
    delete(test_run) if delete?(test_run.split('/').last)
  end
end

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: cleanup.rb [options]'

  opts.on('-v', '--version', 'displays version and exit') do
    puts VERSION
    exit
  end

  opts.on('-h', '--help', 'display help and exit') do
    puts opts
    exit
  end
end

parser.parse!
cleanup
