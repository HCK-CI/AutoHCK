# typed: true
# frozen_string_literal: true

require 'json'
require 'open3'

module AutoHCK
  # Runs shell commands from external_script.json for selected notification hooks.
  # Each hook argument is passed as AUTOHCK_NOTIFICATION_<PARAM_NAME>=<json-encoded value>.

  class ExternalScript
    extend T::Sig
    include Helper
    include NotificationProviderInterface

    CONFIG_JSON = 'lib/notificationmanagers/external_script/external_script.json'
    # API version for the notification hook script
    # Increment API_1 when any field or hook was removed or modified (including name).
    #     Reset API_2 to 0 when API_1 is updated.
    # Increment API_2 when any new field or hook was added.
    AUTOHCK_NOTIFICATION_HOOK_API_1 = '1'
    AUTOHCK_NOTIFICATION_HOOK_API_2 = '0'

    sig { params(project: Project).void }
    def initialize(project)
      @logger = project.logger
      raw = Json.read_json(CONFIG_JSON, @logger)
      @hooks = T.let(normalize_hooks(raw), T::Hash[String, String])
    end

    sig { override.void }
    def close; end

    sig { override.params(project: Project).void }
    def post_project_init(project)
      @project = project

      dispatch(:post_project_init, {})
    end

    sig { override.params(project: Project).void }
    def pre_project_prepare(project)
      @project = project

      dispatch(:pre_project_prepare, {})
    end

    sig { override.params(project: Project).void }
    def post_project_prepare(project)
      @project = project

      dispatch(:post_project_prepare, {})
    end

    sig { override.params(project: Project).void }
    def pre_project_run(project)
      @project = project

      dispatch(:pre_project_run, {})
    end

    sig { override.params(project: Project).void }
    def post_project_run(project)
      @project = project

      dispatch(:post_project_run, {})
    end

    sig { override.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def post_engine_init(engine)
      @engine = engine

      dispatch(:post_engine_init, {})
    end

    sig { override.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def pre_engine_run(engine)
      @engine = engine

      dispatch(:pre_engine_run, {})
    end

    sig { override.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def post_engine_run(engine)
      @engine = engine

      dispatch(:post_engine_run, {})
    end

    sig { override.params(setup_manager: T.any(PhysHCK, QemuHCK)).void }
    def post_setup_manager_init(setup_manager)
      @setup_manager = setup_manager

      dispatch(:post_setup_manager_init, {})
    end

    sig { override.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_hck_studio(setup_manager, run_opts)
      @setup_manager = setup_manager

      dispatch(:pre_setup_manager_run_hck_studio, { run_opts: run_opts })
    end

    sig { override.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_hck_studio(setup_manager, run_opts)
      @setup_manager = setup_manager

      dispatch(:post_setup_manager_run_hck_studio, { run_opts: run_opts })
    end

    sig { override.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_studio(setup_manager, run_opts)
      @setup_manager = setup_manager

      dispatch(:pre_setup_manager_run_studio, { run_opts: run_opts })
    end

    sig { override.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_studio(setup_manager, run_opts)
      @setup_manager = setup_manager

      dispatch(:post_setup_manager_run_studio, { run_opts: run_opts })
    end

    sig do
      override.params(
        setup_manager: T.any(PhysHCK, QemuHCK),
        _studio: HCKStudio,
        name: String,
        run_opts: T::Hash[String, T.untyped]
      ).void
    end
    def pre_setup_manager_run_hck_client(setup_manager, _studio, name, run_opts)
      @setup_manager = setup_manager

      # No useful data in studio, so we don't pass it to the script.
      dispatch(:pre_setup_manager_run_hck_client, { name: name, run_opts: run_opts })
    end

    sig do
      override.params(
        setup_manager: T.any(PhysHCK, QemuHCK),
        _studio: HCKStudio,
        name: String,
        run_opts: T::Hash[String, T.untyped]
      ).void
    end
    def post_setup_manager_run_hck_client(setup_manager, _studio, name, run_opts)
      @setup_manager = setup_manager

      # No useful data in studio, so we don't pass it to the script.
      dispatch(:post_setup_manager_run_hck_client, { name: name, run_opts: run_opts })
    end

    sig do
      override.params(setup_manager: T.any(PhysHCK, QemuHCK), name: String,
                      run_opts: T::Hash[String, T.untyped]).void
    end
    def pre_setup_manager_run_client(setup_manager, name, run_opts)
      @setup_manager = setup_manager

      dispatch(:pre_setup_manager_run_client, { name: name, run_opts: run_opts })
    end

    sig do
      override.params(setup_manager: T.any(PhysHCK, QemuHCK), name: String,
                      run_opts: T::Hash[String, T.untyped]).void
    end
    def post_setup_manager_run_client(setup_manager, name, run_opts)
      @setup_manager = setup_manager

      dispatch(:post_setup_manager_run_client, { name: name, run_opts: run_opts })
    end

    sig { override.params(tests: T::Array[Models::HLK::Test]).void }
    def pre_tests_run(tests)
      dispatch(:pre_tests_run, { tests: tests })
    end

    sig { override.params(tests: T::Array[Models::HLK::Test]).void }
    def post_tests_run(tests)
      dispatch(:post_tests_run, { tests: tests })
    end

    sig { override.params(test: Models::HLK::Test, wait: T::Boolean).void }
    def pre_tests_queue_test(test, wait)
      dispatch(:pre_tests_queue_test, { test: test, wait: wait })
    end

    sig { override.params(test: Models::HLK::Test).void }
    def pre_tests_on_test_start(test)
      dispatch(:pre_tests_on_test_start, { test: test })
    end

    sig do
      override.params(results: T::Array[T::Hash[String, T.untyped]],
                      tests_stats: T::Hash[String, T.untyped]).void
    end
    def pre_tests_handle_finished_test_results(results, tests_stats)
      dispatch(:pre_tests_handle_finished_test_results,
               { results: results, tests_stats: tests_stats })
    end

    sig { override.params(test: Models::HLK::Test, result: T::Hash[String, T.untyped]).void }
    def pre_tests_handle_finished_test_result(test, result)
      dispatch(:pre_tests_handle_finished_test_result,
               { test: test, result: result })
    end

    private

    sig { params(raw: T::Hash[String, T.untyped]).returns(T::Hash[String, String]) }
    def normalize_hooks(raw)
      nested = raw['hooks']
      base = nested.is_a?(Hash) ? T.cast(nested, T::Hash[String, T.untyped]) : raw
      base.each_with_object({}) do |(key, val), acc|
        k = key.to_s
        next if k.start_with?('_')
        next if val.nil?

        s = val.to_s.strip
        next if s.empty?

        acc[k] = s
      end
    end

    sig { params(cmd: String).returns(String) }
    def resolve_command(cmd)
      return cmd if cmd.start_with?('/')

      File.expand_path(cmd, T.must(__dir__))
    end

    # rubocop:disable Metrics/CyclomaticComplexity -- type dispatch for JSON env encoding
    sig { params(value: T.untyped).returns(T.untyped) }
    def to_json_safe(value)
      case value
      when nil then nil
      when String, Numeric, TrueClass, FalseClass then value
      when Symbol then value.to_s
      when Hash then value.transform_values { |v| to_json_safe(v) }
      when Array then value.map { |v| to_json_safe(v) }
      when DateTime, Time then value.iso8601
      when Models::HLK::Test, Models::Driver then value.serialize
      else
        to_json_safe_unknown(value)
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    sig { params(studio: HCKStudio).returns(T::Hash[String, T.untyped]) }
    def hck_studio_payload(studio)
      { 'class' => 'HCKStudio', 'engine_tag' => studio.instance_variable_get(:@tag) }
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    def to_json_safe_unknown(value)
      return value.serialize if value.respond_to?(:serialize)

      { 'class' => value.class.name, 'inspect' => value.inspect.byteslice(0, 16_384) }
    end

    sig { params(value: T.untyped).returns(String) }
    def encode_notification_value(value)
      return '' if value.nil?

      JSON.generate(to_json_safe(value))
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def bound_project_args
      return {} if @project.nil?

      {
        timestamp: @project.timestamp,
        id: @project.id,
        workspace_path: @project.workspace_path,
        engine_tag: @project.engine_tag,
        engine_platform_name: @project.engine_platform['name'],
        engine_type: @project.engine_type&.to_s,
        run_terminated: @project.run_terminated,
        engine_name: @project.engine_name
      }
    end

    def bound_engine_args
      return {} if @engine.nil?

      {
        engine_drivers: @engine.drivers,
        engine_target_name: @engine.target&.dig('name')
      }
    end

    def bound_setup_manager_args
      return {} if @setup_manager.nil?

      {
        setup_manager_kit: @setup_manager.kit
      }
    end

    sig { params(hook: Symbol, bound_args: T::Hash[Symbol, T.untyped]).void }
    def dispatch(hook, bound_args)
      cmd = @hooks[hook.to_s]
      return if cmd.nil? || cmd.strip.empty?

      bound_args = bound_args.merge(bound_project_args).merge(bound_engine_args).merge(bound_setup_manager_args)

      merged_env = merge_notification_env(hook, bound_args)
      execute_notification_script(hook, merged_env, resolve_command(cmd))
    end

    sig { params(hook: Symbol, bound_args: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, String]) }
    def merge_notification_env(hook, bound_args)
      env = {
        'AUTOHCK_NOTIFICATION_HOOK' => hook.to_s,
        'AUTOHCK_NOTIFICATION_HOOK_API_1' => AUTOHCK_NOTIFICATION_HOOK_API_1,
        'AUTOHCK_NOTIFICATION_HOOK_API_2' => AUTOHCK_NOTIFICATION_HOOK_API_2,
        'AUTOHCK_NOTIFICATION_VERSION' => AutoHCK::VERSION.to_s
      }

      bound_args.each do |name, value|
        env[notification_env_key(name)] = encode_notification_value(value)
      end

      ENV.to_h.merge(env)
    end

    sig { params(name: Symbol).returns(String) }
    def notification_env_key(name)
      "AUTOHCK_NOTIFICATION_#{name.to_s.upcase}"
    end

    sig { params(hook: Symbol, merged_env: T::Hash[String, String], script: String).void }
    def execute_notification_script(hook, merged_env, script)
      unless File.exist?(script)
        @logger.warn("ExternalScript: #{hook} script missing: #{script}")
        return
      end
      unless File.executable?(script)
        @logger.warn("ExternalScript: #{hook} script not executable: #{script}")
        return
      end

      out, status = Open3.capture2e(merged_env, script)

      @logger.info("ExternalScript #{hook} finished with code #{status.exitstatus}")
      return if status.success?

      @logger.warn("ExternalScript #{hook} failed (#{status.exitstatus}): #{out}")
    end
  end
end
