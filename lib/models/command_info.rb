# typed: strict
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Models module
  module Models
    class FileActionDirection < T::Enum
      extend T::Sig

      enums do
        RemoteToLocal = new('remote-to-local')
        LocalToRemote = new('local-to-remote')
      end

      sig { returns(String) }
      def to_s
        serialize
      end
    end

    class FileActionConfig < T::Struct
      extend T::Sig
      const :remote_path, T.nilable(String)
      const :local_path, T.nilable(String)
      const :direction, FileActionDirection, default: FileActionDirection::RemoteToLocal
      const :move, T::Boolean, default: false
      const :allow_missing, T::Boolean, default: false

      sig do
        params(replacement: ReplacementMap, default_remote_path: String,
               default_local_path: String).returns(FileActionConfig)
      end
      def dup_and_replace_path(replacement, default_remote_path, default_local_path)
        self.class.new(
          remote_path: replacement.replace(remote_path || default_remote_path),
          local_path: replacement.replace(local_path || default_local_path),
          direction: direction,
          move: move,
          allow_missing: allow_missing
        )
      end
    end

    # CommandInfo class
    class CommandInfo < T::Struct
      extend T::Sig
      extend JsonHelper

      const :desc, String
      const :host_run, T.nilable(String)
      const :guest_run, T.nilable(String)
      const :guest_reboot, T::Boolean, default: false
      const :files_action, T::Array[FileActionConfig], default: []
    end
  end
end
