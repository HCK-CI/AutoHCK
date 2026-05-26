# typed: true
# frozen_string_literal: true

module AutoHCK
  class Session < T::Struct
    extend T::Sig
    extend Models::JsonHelper

    prop :cli, CLI

    sig { params(workspace_path: String, logger: AutoHCK::MultiLogger).void }
    def save(workspace_path, logger)
      data = cli.serialize
      File.write("#{workspace_path}/session.json", data.to_json)
      logger.info("Session saved to #{workspace_path}/session.json")
    end

    sig { params(session_path: String, workspace_path: T.nilable(String)).returns(Session) }
    def self.load(session_path, workspace_path)
      resolved_path = File.realpath(session_path)
      cli = CLI.from_hash(read_session_data(resolved_path))
      cli.common.workspace_path = workspace_path
      cli.test.session = resolved_path
      cli.test.manual = true
      new(cli:)
    rescue SystemCallError, JSON::ParserError => e
      raise AutoHCKError, "Failed to load session from #{session_path}: #{e.message}"
    end

    def self.read_session_data(resolved_path)
      data = JSON.parse(File.read("#{resolved_path}/session.json"))
      data['test']['package_with_driver'] = data['test']['package_with_driver']&.to_sym
      data
    end

    private_class_method :read_session_data
  end
end
