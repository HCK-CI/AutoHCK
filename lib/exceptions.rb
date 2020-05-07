# frozen_string_literal: true

# A custom AutoHCK error exception
class AutoHCKError < StandardError; end

class EngineError < AutoHCKError; end
# A custom CmdRun error exception
class CmdRunError < EngineError; end
# A custom Invalid Paths Error exception
class InvalidPathError < EngineError; end
# A custom Invalid Config File error exception
class InvalidConfigFile < EngineError; end
# A custom Invalid Engine Type error exception
class InvalidEngineTypeError < EngineError; end
# A custom Could not open json file
class OpenJsonError < StandardError; end
class SetupManagerError < StandardError; end
