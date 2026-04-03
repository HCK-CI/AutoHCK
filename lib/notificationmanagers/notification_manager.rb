# frozen_string_literal: true

module AutoHCK
  class NotificationManager
    class ProviderFactory
      PROVIDERS = Dir.each_child(__dir__).filter_map do |provider_name|
        full_path = "#{__dir__}/#{provider_name}"
        next unless File.directory?(full_path)

        file = "#{full_path}/#{provider_name}.rb"
        require file
        # Convert 'result_uploader' (file name) -> 'ResultUploader' (class name)
        class_name = provider_name.camelize
        # Convert 'ResultUploader' (class name) -> ResultUploader (declared constant)
        # or
        # Convert 'ResultUploader' (class name) -> AutoHCK::ResultUploader (declared constant)
        [provider_name, AutoHCK.const_get(class_name)]
      end.to_h.freeze

      def self.create(type, project)
        PROVIDERS[type].new(project)
      end

      def self.can_create?(type)
        !PROVIDERS[type].nil?
      end
    end

    def initialize(scope, project)
      @scope = scope
      @providers = {}
      types = Array(project.config['notification_providers']).compact.uniq
      types.each do |type|
        if ProviderFactory.can_create?(type)
          @scope << (@providers[type] = ProviderFactory.create(type, project))
        else
          project.logger.info("Unknown notification provider #{type}, (ignoring)")
        end
      end
    end

    def post_project_init(project)
      @providers.each_value { |p| p.post_project_init(project) }
    end

    def pre_project_prepare(project)
      @providers.each_value { |p| p.pre_project_prepare(project) }
    end

    def post_project_prepare(project)
      @providers.each_value { |p| p.post_project_prepare(project) }
    end

    def pre_project_run(project)
      @providers.each_value { |p| p.pre_project_run(project) }
    end

    def post_project_run(project)
      @providers.each_value { |p| p.post_project_run(project) }
    end

    def post_engine_init(engine)
      @providers.each_value { |p| p.post_engine_init(engine) }
    end

    def pre_engine_run(engine)
      @providers.each_value { |p| p.pre_engine_run(engine) }
    end

    def post_engine_run(engine)
      @providers.each_value { |p| p.post_engine_run(engine) }
    end

    def post_setup_manager_init(setup_manager)
      @providers.each_value { |p| p.post_setup_manager_init(setup_manager) }
    end

    def pre_setup_manager_run_hck_studio(setup_manager, run_opts)
      @providers.each_value { |p| p.pre_setup_manager_run_hck_studio(setup_manager, run_opts) }
    end

    def post_setup_manager_run_hck_studio(setup_manager, run_opts)
      @providers.each_value { |p| p.post_setup_manager_run_hck_studio(setup_manager, run_opts) }
    end

    def pre_setup_manager_run_studio(setup_manager, run_opts)
      @providers.each_value { |p| p.pre_setup_manager_run_studio(setup_manager, run_opts) }
    end

    def post_setup_manager_run_studio(setup_manager, run_opts)
      @providers.each_value { |p| p.post_setup_manager_run_studio(setup_manager, run_opts) }
    end

    def pre_setup_manager_run_hck_client(setup_manager, studio, name, run_opts)
      @providers.each_value { |p| p.pre_setup_manager_run_hck_client(setup_manager, studio, name, run_opts) }
    end

    def post_setup_manager_run_hck_client(setup_manager, studio, name, run_opts)
      @providers.each_value { |p| p.post_setup_manager_run_hck_client(setup_manager, studio, name, run_opts) }
    end

    def pre_setup_manager_run_client(setup_manager, name, run_opts)
      @providers.each_value { |p| p.pre_setup_manager_run_client(setup_manager, name, run_opts) }
    end

    def post_setup_manager_run_client(setup_manager, name, run_opts)
      @providers.each_value { |p| p.post_setup_manager_run_client(setup_manager, name, run_opts) }
    end

    def pre_tests_run(tests)
      @providers.each_value { |p| p.pre_tests_run(tests) }
    end

    def post_tests_run(tests)
      @providers.each_value { |p| p.post_tests_run(tests) }
    end

    def pre_tests_queue_test(test, wait)
      @providers.each_value { |p| p.pre_tests_queue_test(test, wait) }
    end

    def pre_tests_on_test_start(test)
      @providers.each_value { |p| p.pre_tests_on_test_start(test) }
    end

    def pre_tests_handle_finished_test_results(results, tests_stats)
      @providers.each_value { |p| p.pre_tests_handle_finished_test_results(results, tests_stats) }
    end

    def pre_tests_handle_finished_test_result(test, result)
      @providers.each_value { |p| p.pre_tests_handle_finished_test_result(test, result) }
    end
  end
end
