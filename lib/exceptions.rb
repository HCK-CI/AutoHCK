# frozen_string_literal: true

# A custom AutoHCK error exception
class AutoHCKError < StandardError; end

# A custom GithubCommitInvalid error exception
class GithubCommitInvalid < AutoHCKError; end

# A custom Could not open json file exception
class OpenJsonError < StandardError; end

# A custom Could not open XML file exception
class OpenXmlError < StandardError; end