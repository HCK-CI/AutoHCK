# frozen_string_literal: true

module AutoHCK
  # A custom RToolsHCK error exception
  class RToolsHCKError < AutoHCKError
    # Custom addition to the exception backtrace, (better logging)
    attr_reader :where

    # Initialization of the custom exception
    def initialize(where)
      @where = where
      super
    end
  end

  # A custom RToolsHCK connection error exception
  class RToolsHCKConnectionError < RToolsHCKError; end

  # A custom RToolsHCK action error exception
  class RToolsHCKActionError < RToolsHCKError; end

  # A custom Winrm powershell run error exception
  class WinrmPSRunError < RToolsHCKActionError; end

  # A custom Server error exception
  class ServerError < RToolsHCKConnectionError; end

  # A custom Ether error exception
  class EtherError < RToolsHCKConnectionError; end
end
