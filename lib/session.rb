# frozen_string_literal: true

module AutoHCK
  class Session < T::Struct
    extend T::Sig
    extend Models::JsonHelper

    prop :common, CommonOptions
    prop :test, TestOptions
    prop :install, InstallOptions
    prop :mode, T.nilable(String), default: nil

    sig { params(workspace_path: String, cli: CLI, logger: AutoHCK::MultiLogger).void }
    def self.save(workspace_path, cli, logger)
      File.write("#{workspace_path}/session.json", cli.serialize.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    sig { params(session_path: String, cli: CLI).returns(Session) }
    def self.load(session_path, cli)
      session = AutoHCK::Session.from_json_file("#{session_path}/session.json")

      session.common.workspace_path = cli.common.workspace_path
      session.test.session = session_path
      session.test.manual = true
      session
    end
  end
end
