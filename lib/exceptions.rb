# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # A custom AutoHCK error exception
  class AutoHCKError < StandardError; end

  # A custom GithubCommitInvalid error exception
  class GithubCommitInvalid < AutoHCKError; end

  # A custom Could not open json file exception
  class OpenJsonError < StandardError; end
end
