# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

require_relative 'json_helper'

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # CommandInfo class
    class CommandInfo < T::Struct
      extend T::Sig
      extend JsonHelper

      const :desc, String
      const :run, String
    end
  end
end
