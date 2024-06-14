# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # A custom EngineError
  class EngineError < AutoHCKError; end

  # A custom Invalid Engine Type error exception
  class InvalidEngineTypeError < EngineError; end
end
