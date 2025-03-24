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
    def load(session_path, workspace_path)
      session = Session.from_json_file("#{session_path}/session.json")
      @cli = load_cli(session, session_path, workspace_path)
      session
    end

    private

    sig { params(session: Session, session_path: String, workspace_path:T.nilable(String)).returns(CLI) }
    def load_cli(session, session_path, workspace_path)
      T.must(session.cli.common).workspace_path = workspace_path
      T.must(session.cli.test).session = session_path
      T.must(session.cli.test).manual = true
      session.cli
    end
  end
end
