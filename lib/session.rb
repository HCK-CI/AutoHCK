# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize,Metrics/MethodLength, Lint/MissingCopEnableDirective, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

module AutoHCK
  class Session
    extend T::Sig
    include Helper

    def self.save(workspace_path, options)
      File.write("#{workspace_path}/session.json", compose_session_json(options))
    end

    def self.load(cli)
      session = Models::Session.from_json_file("#{session_path(cli)}/session.json")

      cli.test.platform = session.test.platform
      cli.test.drivers = session.test.drivers
      cli.test.driver_path ||= session.test.driver_path
      cli.test.commit ||= session.test.commit
      cli.test.svvp = session.test.svvp
      cli.test.dump ||= session.test.dump
      cli.test.gthb_context_prefix ||= session.test.gthb_context_prefix
      cli.test.gthb_context_suffix ||= session.test.gthb_context_suffix
      cli.test.playlist ||= session.test.playlist
      cli.test.select_test_names ||= session.test.select_test_names
      cli.test.reject_test_names ||= session.test.reject_test_names
      cli.test.reject_report_sections ||= session.test.reject_report_sections
      cli.test.boot_device ||= session.test.boot_device
      cli.test.allow_test_duplication ||= session.test.allow_test_duplication
      cli.test.manual ||= true
      cli.test.package_with_playlist |= session.test.package_with_playlist
      cli.test.session = session_path(cli)
      cli.test.latest_session ||= session.test.latest_session
      cli.common.verbose ||= session.common.verbose
      cli.common.config ||= session.common.config
      cli.common.client_world_net ||= session.common.client_world_net
      cli.common.id ||= session.common.id
      cli.common.share_on_host_path ||= session.common.share_on_host_path
    end

    def self.session_path(cli)
      cli.test.latest_session ? "#{Config.read['workspace_path']}/latest" : cli.test.session
    end

    private_class_method def self.compose_session_json(options)
      {
        test: options.test.serialize,
        common: options.common.serialize
      }.to_json
    end
  end
end
