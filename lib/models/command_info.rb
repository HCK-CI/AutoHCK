# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    # CommandInfo class
    class CommandInfo < T::Struct
      extend T::Sig
      extend JsonHelper

      const :desc, String
      const :host_run, T.nilable(String)
      const :guest_run, T.nilable(String)
      const :guest_reboot, T::Boolean, default: false
    end
  end
end
