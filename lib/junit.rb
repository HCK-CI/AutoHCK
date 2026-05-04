# frozen_string_literal: true

module AutoHCK
  class JUnit
    path = 'lib/templates/junit.xml.erb'
    template = Erubi::Engine.new(File.read(path), escape: true)

    # rubocop:disable Security/Eval,Style/DocumentDynamicEvalDefinition
    binding.eval "def build_xml; #{template.src}; end", path
    # rubocop:enable Security/Eval,Style/DocumentDynamicEvalDefinition

    def initialize(project)
      @project = project
      @logger = project.logger
    end

    def run_property_drivers
      return if @project.engine&.drivers.nil?

      @project.engine.drivers.map(&:short).join(',')
    end

    def project_properties
      {
        'engine' => @project.engine_name,
        'platform' => @project.engine_platform&.dig('name') || 'unknown',
        'svvp' => @project.options.test.svvp,
        'drivers' => run_property_drivers,
        'results_url' => @project.result_uploader&.url,
        'results_html' => @project.result_uploader&.html_url,
        'status' => @project.status.to_s,
        'engine_test_steps_count' => @project.engine.test_steps.count
      }
    end

    def setup_manager_properties
      sm = @project.setup_manager
      {
        'hypervisor' => sm&.hypervisor_info,
        'hypervisor_package' => sm&.hypervisor_package_info,
        'hypervisor_dependencies_package' => sm&.hypervisor_dependencies_package_info,
        'host' => sm&.host_info
      }
    end

    def run_properties
      project_properties.merge(setup_manager_properties)
    end

    def tag
      @project.engine_tag
    end

    def auto_hck_log
      @project.string_log.string
    end

    def timestamp
      Time.strptime(@project.timestamp, '%Y_%m_%d_%H_%M_%S').iso8601
    end

    def engine_test_steps
      return [] if @project&.engine&.test_steps.nil?

      @project.engine.test_steps.select do |step|
        step.is_skipped ||
          [Models::HLK::TestResultStatus::Failed,
           Models::HLK::TestResultStatus::Passed].include?(step.status)
      end
    end

    def autohck_project_status
      @project.status
    end

    def junit_failed_test_steps_count
      engine_test_steps.count { _1.status == Models::HLK::TestResultStatus::Failed }
    end

    def junit_suite_tests_count
      engine_test_steps.count + 1
    end

    def junit_suite_failures_count
      junit_failed_test_steps_count + (autohck_project_status == :failed ? 1 : 0)
    end

    def junit_suite_errors_count
      autohck_project_status == :error ? 1 : 0
    end

    def junit_suite_skipped_count
      engine_test_steps.count(&:is_skipped) +
        (%i[canceled running].include?(autohck_project_status) ? 1 : 0)
    end

    def generate(file_path)
      @logger.info('Generating JUnit report')

      File.write(file_path, build_xml)
    end
  end
end
