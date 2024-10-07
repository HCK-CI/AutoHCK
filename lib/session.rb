# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize,Metrics/MethodLength, Lint/MissingCopEnableDirective

module AutoHCK
  class Session
    def self.save(workspace_path, options)
      File.write("#{workspace_path}/session.json", compose_session_json(options))
    end

    def self.load_session_cli(cli)
      json_data = JSON.parse(File.read("#{cli.test.load_session}/session.json"))
      cli.test.platform = json_data['test']['platform']
      cli.test.drivers = json_data['test']['drivers']
      cli.test.driver_path = json_data['test']['driver_path']
      cli.test.commit = json_data['test']['commit']
      cli.test.diff_file = json_data['test']['diff_file']
      cli.test.svvp = json_data['test']['svvp']
      cli.test.dump = json_data['test']['dump']
      cli.test.gthb_context_prefix = json_data['test']['gthb_context_prefix']
      cli.test.gthb_context_suffix = json_data['test']['gthb_context_suffix']
      cli.test.playlist = json_data['test']['playlist']
      cli.test.select_test_names = json_data['test']['select_test_names']
      cli.test.reject_test_names = json_data['test']['reject_test_names']
      cli.test.triggers_file = json_data['test']['triggers_file']
      cli.test.reject_report_sections = json_data['test']['reject_report_sections']
      cli.test.boot_device = json_data['test']['boot_device']
      cli.test.allow_test_duplication = json_data['test']['allow_test_duplication']
      cli.test.manual = json_data['test']['manual']
      cli.test.package_with_playlist = json_data['test']['package_with_playlist']
      cli.test.load_session = json_data['test']['load_session']
      cli.common.verbose = json_data['common']['verbose']
      cli.common.config = json_data['common']['config']
      cli.common.client_world_net = json_data['common']['client_world_net']
      cli.common.id = json_data['common']['id']
      cli.common.share_on_host_path = json_data['common']['share_on_host_path']
    end

    private_class_method def self.compose_session_json(options)
      {
        'test' => {
          'platform' => options.test.platform,
          'drivers' => options.test.drivers,
          'driver_path' => options.test.driver_path,
          'commit' => options.test.commit,
          'diff_file' => options.test.diff_file,
          'svvp' => options.test.svvp,
          'dump' => options.test.dump,
          'gthb_context_prefix' => options.test.gthb_context_prefix,
          'gthb_context_suffix' => options.test.gthb_context_suffix,
          'playlist' => options.test.playlist,
          'select_test_names' => options.test.select_test_names,
          'reject_test_names' => options.test.reject_test_names,
          'triggers_file' => options.test.triggers_file,
          'reject_report_sections' => options.test.reject_report_sections,
          'boot_device' => options.test.boot_device,
          'allow_test_duplication' => options.test.allow_test_duplication,
          'manual' => options.test.manual,
          'package_with_playlist' => options.test.package_with_playlist
        },
        'common' => {
          'verbose' => options.common.verbose,
          'config' => options.common.config,
          'client_world_net' => options.common.client_world_net,
          'id' => options.common.id,
          'share_on_host_path' => options.common.share_on_host_path
        }
      }.to_json
    end
  end
end
