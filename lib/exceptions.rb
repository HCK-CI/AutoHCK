# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # A custom AutoHCK error exception
  class AutoHCKError < StandardError; end

  # A custom AutoHCK interrupt exception that can be safely blocked with
  # Thread.handle_interrupt without blocking the other exceptions.
  # rubocop:disable Lint/InheritException
  class AutoHCKInterrupt < Exception; end
  # rubocop:enable Lint/InheritException

  # A custom GithubCommitInvalid error exception
  class GithubCommitInvalid < AutoHCKError; end

  # A custom Could not open json file exception
  class OpenJsonError < StandardError; end

  # A custom CmdRun error exception
  class CmdRunError < AutoHCKError; end

  # A custom Invalid Paths Error exception
  class InvalidPathError < AutoHCKError; end

  # A custom Invalid Config File error exception
  class InvalidConfigFile < AutoHCKError; end

  # A custom Not Implemented feature error error exception
  class NotImplementedError < AutoHCKError; end
end
