#frozen_string_literal: true

require 'json'
require 'fileutils'
require './lib/exceptions'

def read_json(json_file,logger)
  JSON.parse(File.read(json_file))
rescue Errno::ENOENT, JSON::ParserError
  logger.fatal("Could not open #{json_file} file")
  raise OpenJsonError, "Could not open #{json_file} file"
end
