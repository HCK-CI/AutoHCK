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

    class QmpCommandConfig < T::Struct
      extend T::Sig

      const :execute, String
      const :arguments, T.nilable(T::Hash[String, T.untyped])
    end

    class QmpWaitEventConfig < T::Struct
      extend T::Sig

      # List of event names to wait for; returns as soon as any one of
      # them occurs (e.g. a device that may emit either one).
      const :events, T::Array[String]
      const :timeout, T.nilable(Integer)
    end

    class EngineSetupManagerActions < T::Enum
      extend T::Sig

      enums do
        Shutdown = new('shutdown')
        PowerOff = new('power-off')
        PowerOn = new('power-on')
        PowerOnWait = new('power-on-wait')
        Reboot = new('reboot')
        RebootWait = new('reboot-wait')
        ValidatePowerDown = new('validate-power-down')
        ValidatePowerOn = new('validate-power-on')
      end

      sig { returns(String) }
      def to_s
        serialize
      end
    end

    # Unified command/step descriptor for HCK test hooks, post-start commands,
    # and functest JSON steps.
    class CommandInfo < T::Struct
      extend T::Sig
      extend JsonHelper

      prop :desc, String
      const :timeout, T.nilable(Integer)
      const :capture_output, T.nilable(String)
      const :ignore_errors, T.nilable(T::Boolean)
      const :variables, T::Hash[String, String], default: {}

      const :guest_run, T.nilable(String)
      const :guest_run_file, T.nilable(String)
      const :guest_reboot, T::Boolean, default: false
      const :files_action, T::Array[FileActionConfig], default: []
      const :host_run, T.nilable(String)
      const :host_run_file, T.nilable(String)
      const :barrier, T.nilable(String)
      const :set_variable, T.nilable(T::Hash[String, String])
      const :qmp_command, T.nilable(QmpCommandConfig)
      const :qmp_wait_event, T.nilable(QmpWaitEventConfig)
      const :engine_setup_manager_action, T.nilable(EngineSetupManagerActions)

      const :expected_output_contains, T.nilable(String)
      const :expected_output_matches, T.nilable(String)
      const :expected_output_matches_encoding, T.nilable(String)

      # Client ids (e.g. 1, 2) this step targets, by position in the platform
      # JSON's clients map. Empty (default) broadcasts to every client in
      # the current test case.
      const :clients, T::Array[Integer], default: []
    end
  end
end
