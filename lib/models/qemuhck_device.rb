# typed: strict
# frozen_string_literal: true

module AutoHCK
  module Models
    class QemuHCKDevice < T::Struct
      extend T::Sig
      extend JsonHelper

      const :name, String
      const :type, T.nilable(String)
      const :command_line, T::Array[String]
      const :define_variables, T.nilable(T::Hash[String, String])
      const :config_commands, T.nilable(T::Array[String])
      const :pre_start_commands, T.nilable(T::Array[String])
      const :post_stop_commands, T.nilable(T::Array[String])
    end
  end
end
