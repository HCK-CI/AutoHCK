# frozen_string_literal: true

require './lib/exceptions'

# AutoHCK module
module AutoHCK
  # A custom ExtraSoftwareMissingConfig error exception
  class ExtraSoftwareMissingConfig < AutoHCKError; end

  # A custom ExtraSoftwareBrokenConfig error exception
  class ExtraSoftwareBrokenConfig < AutoHCKError; end
end
