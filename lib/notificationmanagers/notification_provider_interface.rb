# typed: true
# frozen_string_literal: true

module AutoHCK
  module NotificationProviderInterface
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.void }
    def close; end

    sig { abstract.params(project: Project).void }
    def post_project_init(project); end

    sig { abstract.params(project: Project).void }
    def pre_project_prepare(project); end

    sig { abstract.params(project: Project).void }
    def post_project_prepare(project); end

    sig { abstract.params(project: Project).void }
    def pre_project_run(project); end

    sig { abstract.params(project: Project).void }
    def post_project_run(project); end

    sig { abstract.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def post_engine_init(engine); end

    sig { abstract.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def pre_engine_run(engine); end

    sig { abstract.params(engine: T.any(HCKTest, HCKInstall, ConfigManager)).void }
    def post_engine_run(engine); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK)).void }
    def post_setup_manager_init(setup_manager); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_hck_studio(setup_manager, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_hck_studio(setup_manager, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_studio(setup_manager, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_studio(setup_manager, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), studio: HCKStudio, name: String, run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_hck_client(setup_manager, studio, name, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), studio: HCKStudio, name: String, run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_hck_client(setup_manager, studio, name, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), name: String, run_opts: T::Hash[String, T.untyped]).void }
    def pre_setup_manager_run_client(setup_manager, name, run_opts); end

    sig { abstract.params(setup_manager: T.any(PhysHCK, QemuHCK), name: String, run_opts: T::Hash[String, T.untyped]).void }
    def post_setup_manager_run_client(setup_manager, name, run_opts); end

    sig { abstract.params(tests: T::Array[Models::HLK::Test]).void }
    def pre_tests_run(tests); end

    sig { abstract.params(tests: T::Array[Models::HLK::Test]).void }
    def post_tests_run(tests); end

    sig { abstract.params(test: Models::HLK::Test, wait: T::Boolean).void }
    def pre_tests_queue_test(test, wait); end

    sig { abstract.params(test: Models::HLK::Test).void }
    def pre_tests_on_test_start(test); end

    sig { abstract.params(results: T::Array[T::Hash[String, T.untyped]], tests_stats: T::Hash[String, Integer]).void }
    def pre_tests_handle_finished_test_results(results, tests_stats); end

    sig { abstract.params(test: Models::HLK::Test, result: T::Hash[String, T.untyped]).void }
    def pre_tests_handle_finished_test_result(test, result); end
  end
end
