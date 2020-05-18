#frozen_string_literal: true
require './lib/exceptions'

# A custom SetupManager error exception
class SetupManagerError < AutoHCKError; end

# A custom StudioConnect error exception
class StudioConnectError < AutoHCKError; end

# custom machine error
class MachineError < AutoHCKError; end
class MachinePidNil < MachineError; end
class MachineRunError < MachineError; end
