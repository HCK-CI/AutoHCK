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
        'svvp' => @project.options.test.svvp,
        'results_url' => @project.result_uploader&.url,
        'results_html' => @project.result_uploader&.html_url,
        'status' => @project.status.to_s,
        'report_generation_time' => generation_time,
        'whiteboard' => @project.whiteboard
      }
    end

    def engine_properties
      {
        'engine' => @project.engine_name,
        'platform' => @project.engine_platform&.name || 'unknown',
        'drivers' => run_property_drivers,
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
      project_properties.merge(setup_manager_properties).merge(engine_properties)
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

    def generation_time
      Time.now.iso8601
    end

    def engine_test_steps
      return [] if @project&.engine&.test_steps.nil?

      @project.engine.test_steps.select do |step|
        step.is_skipped || step.passed? || step.failed?
      end
    end

    def autohck_project_status
      @project.status
    end

    def junit_failed_test_steps_count
      engine_test_steps.count { _1.failed? && _1.errata.nil? }
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

    # XML 1.0 allows only #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] |
    # [#x10000-#x10FFFF]: the C0 control characters (except tab/LF/CR) and
    # U+FFFE/U+FFFF are forbidden. The session log embedded in <system-err>
    # carries raw tool output, and tools can print arbitrary bytes
    # (viosocklib-test echoes an uninitialized recv buffer after a 0-byte
    # recv): a single control character made the whole junit.xml
    # unparseable, and strict consumers silently dropped such runs.
    # Erubi's escape covers the XML entities but not control characters,
    # and forbidden characters have no legal escaped form
    # (character references like &#x4; are themselves illegal), so strip
    # them from the rendered document before it is written. String#scrub
    # also converts invalid UTF-8 bytes to U+FFFD, which is legal.
    def sanitize_xml(text)
      text.scrub.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE-\uFFFF]/, '')
    end

    def generate(file_path)
      @logger.info('Generating JUnit report')

      File.write(file_path, sanitize_xml(build_xml))
    end
  end
end
