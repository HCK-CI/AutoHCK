# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # A custom AutoHCK error exception
  class AutoHCKError < StandardError; end

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
end
