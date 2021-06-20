# frozen_string_literal: true

require_relative '../exceptions'

# AutoHCK module
module AutoHCK
  # A custom QemuHCKError error exception
  class QemuHCKError < SetupManagerError; end
end
