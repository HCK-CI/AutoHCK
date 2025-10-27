# typed: strict
# frozen_string_literal: true

module AutoHCK
  # Models module
  module Models
    # Helper module
    module JsonHelper
      extend T::Sig
      extend T::Generic

      abstract!

      has_attached_class!(:out)

      sig { abstract.params(hash: T::Hash[String, T.untyped]).returns(T.attached_class) }
      def from_hash(hash); end

      sig { params(json_file: String, logger: T.nilable(T.any(MultiLogger, ::Logger))).returns(T.attached_class) }
      def from_json_file(json_file, logger = nil)
        from_hash(AutoHCK::Helper::Json.read_json(json_file, logger))
      end
    end
  end
end
