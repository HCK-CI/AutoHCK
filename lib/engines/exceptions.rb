# frozen_string_literal: true

require './lib/exceptions'

# AutoHCK module
module AutoHCK
  # A custom EngineError
  class EngineError < AutoHCKError; end

  # A custom Invalid Engine Type error exception
  class InvalidEngineTypeError < EngineError; end
end
