# frozen_string_literal: true

module AutoHCK
  # HTML/YAML test results report (results.html, results.yaml), uploaded like junit.xml.
  class ResultReport
    DEFAULT_SECTIONS = %w[chart guest_info host_info rejected_test url].freeze

    def initialize(project)
      @project = project
      @logger = project.logger
      @template = ERB.new(File.read('lib/templates/report.html.erb'))
    end

    def generate(html_path, yaml_path)
      @logger.info('Generating HTML results report')

      steps = @project.engine.test_steps
      data = report_data(steps)

      File.write(html_path, @template.result_with_hash(data))
      File.write(yaml_path, data.to_yaml)
    end

    private

    def report_data(test_steps)
      {
        'tag' => @project.engine_tag,
        'test_stats' => test_stats(test_steps),
        'test_steps' => test_steps,
        'url' => @project.result_uploader.url,
        'system_info' => {
          'guest' => @project.engine.clients_system_info,
          'host' => build_host_info
        },
        'sections' => DEFAULT_SECTIONS - @project.options.test.reject_report_sections
      }
    end

    def test_stats(test_steps)
      run_steps = test_steps.reject(&:is_skipped)
      passed = run_steps.count do |t|
        t.status == Models::HLK::TestResultStatus::Passed &&
          t.executionstate == Models::HLK::ExecutionState::NotRunning
      end
      failed = run_steps.count do |t|
        t.status == Models::HLK::TestResultStatus::Failed &&
          t.executionstate == Models::HLK::ExecutionState::NotRunning
      end
      total = run_steps.count
      skipped = test_steps.count(&:is_skipped)

      {
        'passed' => passed,
        'failed' => failed,
        'inqueue' => total - passed - failed,
        'skipped' => skipped
      }
    end

    def build_host_info
      host_info = {}
      sm = @project.setup_manager
      host_info['Host info'] = sm.host_info

      qemu_version = sm.hypervisor_package_info
      host_info['QEMU package version'] = qemu_version unless qemu_version.nil? || qemu_version.empty?
      sm.hypervisor_dependencies_package_info.each do |info|
        info_value = info[:value]
        host_info[info[:name]] = info_value unless info_value.nil? || info_value.empty?
      end

      host_info
    end
  end
end
