# frozen_string_literal: true

module AutoHCK
  module Session
    extend T::Sig
    include Helper

    def self.save(workspace_path, options, logger)
      File.write("#{workspace_path}/session.json", options.serialize.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    def self.load(cli)
      session = load_session(cli)

      cli.test = session.test
      cli.common = session.common

      cli.test.manual = true
    end

    def self.load_session(cli)
      session = AutoHCK::CLI.from_json_file("#{session_path(cli)}/session.json")

      session.common.workspace_path = cli.common.workspace_path
      session.test.latest_session = cli.test.latest_session
      session.test.session = session_path(cli)

      session
    end

    def self.session_path(cli)
      cli.test.latest_session ? "#{Config.read['workspace_path']}/latest" : cli.test.session
    end
  end
end
