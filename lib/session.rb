# frozen_string_literal: true

module AutoHCK
  module Session
    extend T::Sig
    include Helper

    def self.save(workspace_path, options, logger)
      File.write("#{workspace_path}/session.json", options.serialize.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    def self.load(session_path, cli)
      session = AutoHCK::CLI.from_json_file("#{session_path}/session.json")

      session.common.workspace_path = cli.common.workspace_path
      session.test.session = session_path
      session.test.manual = true
      session
    end
  end
end
