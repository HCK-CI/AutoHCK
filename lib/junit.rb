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

    def run_properties
      {
        'engine' => @project.engine_name,
        'platform' => @project.engine_platform&.dig('name') || 'unknown',
        'svvp' => @project.options.test.svvp,
        'drivers' => run_property_drivers,
        'hypervisor' => @project.setup_manager&.hypervisor_info,
        'host' => @project.setup_manager&.host_info,
        'results_url' => @project.result_uploader&.url,
        'results_html' => @project.result_uploader&.html_url
      }
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
          [AutoHCK::Models::HLK::TestResultStatus::Failed,
           AutoHCK::Models::HLK::TestResultStatus::Passed].include?(step.status)
      end
    end

    def generate(file_path)
      @logger.info('Generating JUnit report')

      File.write(file_path, build_xml)
    end
  end
end
