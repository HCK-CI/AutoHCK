# typed: true
# frozen_string_literal: true

module AutoHCK
  class Session < T::Struct
    extend T::Sig
    extend Models::JsonHelper

    prop :cli, CLI

    sig { params(workspace_path: String, cli: CLI, logger: AutoHCK::MultiLogger).void }
    def self.save_cli(workspace_path, cli, logger)
      File.write("#{workspace_path}/session.json", cli.serialize.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    sig { params(session_path: String, workspace_path: T.nilable(String)).returns(CLI) }
    def self.load_cli(session_path, workspace_path)
      cli = CLI.from_json_file("#{session_path}/session.json")

      T.must(cli.common).workspace_path = workspace_path
      T.must(cli.test).session = session_path
      T.must(cli.test).manual = true
      cli
    end
  end
end
