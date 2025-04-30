# frozen_string_literal: true

module AutoHCK
  class JUnit
    def initialize(project)
      @project = project
      @logger = project.logger

      @template = Erubi::Engine.new(File.read('lib/templates/junit.xml.erb'), escape: true)
    end

    def run_property_drivers
      return if @project.engine&.drivers.nil?

      @project.engine.drivers.map(&:short).join(',')
    end

    def run_properties
      {
        'engine' => @project.engine_name,
        'platform' => @project.engine_platform['name'],
        'svvp' => @project.options.test.svvp,
        'drivers' => run_property_drivers,
        'hypervisor' => @project.setup_manager&.hypervisor_info,
        'host' => @project.setup_manager&.host_info,
        'results_url' => @project.result_uploader&.url,
        'results_html' => @project.result_uploader&.html_url
      }
    end

    def set_report_data
      @tag = @project.engine_tag
      @auto_hck_log = @project.string_log.string
      @timestamp = Time.strptime(@project.timestamp, '%Y_%m_%d_%H_%M_%S').iso8601
    end

    def engine_test_steps
      return [] if @project&.engine&.test_steps.nil?

      @project.engine.test_steps.select do |step|
        [AutoHCK::Models::HLK::TestResultStatus::Failed,
         AutoHCK::Models::HLK::TestResultStatus::Passed].include?(step.status)
      end
    end

    def generate_junit_report(file_path)
      @logger.info('Generating JUnit report')
      set_report_data
      @logger.debug("Writing JUnit report to #{file_path}")

      # rubocop:disable Security/Eval
      File.write(file_path, eval(@template.src))
      # rubocop:enable Security/Eval
    end
  end
end
