# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # A custom QemuHCKError error exception
  class QemuHCKError < SetupManagerError; end

  class QemuRunError < QemuHCKError; end
end
