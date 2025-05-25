# typed: true
# frozen_string_literal: true

module AutoHCK
  class Session < T::Struct
    extend T::Sig
    extend Models::JsonHelper

    prop :cli, CLI

    sig { params(workspace_path: String, logger: AutoHCK::MultiLogger).void }
    def save(workspace_path, logger)
      File.write("#{workspace_path}/session.json", serialize.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    sig { params(session_path: String, workspace_path: T.nilable(String)).returns(Session) }
    def self.load(session_path, workspace_path)
      session = Session.from_json_file("#{session_path}/session.json")
      session.cli.common.workspace_path = workspace_path
      session.cli.test.session = session_path
      session.cli.test.manual = true
      session
    end
  end
end
