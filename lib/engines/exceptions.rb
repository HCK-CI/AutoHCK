#frozen_string_literal: true

require './lib/exceptions'
# A custom EngineError
class EngineError < AutoHCKError; end
# A custom CmdRun error exception
class CmdRunError < EngineError; end
# A custom Invalid Paths Error exception
class InvalidPathError < EngineError; end
# A custom Invalid Config File error exception
class InvalidConfigFile < EngineError; end
# A custom Invalid Engine Type error exception
class InvalidEngineTypeError < EngineError; end
