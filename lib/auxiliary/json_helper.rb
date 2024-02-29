# typed: false
# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/hash/deep_merge'
require 'json'
require 'fileutils'
require 'sorbet-runtime'
require './lib/exceptions'
require './lib/auxiliary/multi_logger'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    # Json class
    class Json
      extend T::Sig

      @json_override_file = 'override.json'

      def self.update_json_override(json_file)
        @json_override_file = json_file
      end

      sig do
        params(json_file: String, logger: T.nilable(T.any(MultiLogger, ::Logger))).returns(T::Hash[String, T.untyped])
      end
      def self.read_json(json_file, logger = nil)
        data = JSON.parse(File.read(json_file))

        if File.exist?(@json_override_file)
          override = JSON.parse(File.read(@json_override_file))
          data.deep_merge!(override[json_file].to_h)
        end

        data
      rescue Errno::ENOENT, JSON::ParserError
        logger&.fatal("Could not open #{json_file} file")
        raise OpenJsonError, "Could not open #{json_file} file"
      end
    end
  end
end
