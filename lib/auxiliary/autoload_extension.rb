# frozen_string_literal: true

module AutoHCK
  module AutoloadExtension
    private

    def autoload_relative(symbol, file)
      relative_from = caller_locations(1..1).first
      relative_from_path = relative_from.absolute_path || relative_from.path
      autoload symbol, File.expand_path("../#{file}", relative_from_path)
    end
  end
end
