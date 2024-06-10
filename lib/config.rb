# frozen_string_literal: true

module AutoHCK
  module Config
    def self.read(logger = nil)
      Helper::Json.read_json('config.json', logger)
    end
  end
end
