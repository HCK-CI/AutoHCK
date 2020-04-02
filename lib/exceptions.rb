# frozen_string_literal: true

# A custom AutoHCK error exception
class AutoHCKError < StandardError; end

class EngineError < AutoHCKError; end
# A custom CmdRun error exception
class CmdRunError < EngineError; end
# A custom Invalid Paths Error exception
class InvalidPathError < EngineError; end
