# frozen_string_literal: true

module AutoHCK
  module Functest
    module DynamicTests
      def self.vm_pause_resume
        VmPauseResume
      end

      # Ruby rewrite of the QMP stop/cont pattern used by JSON cases such as
      # pvpanic/pvpanic_with_stop_continue, plus query-status checks that are
      # awkward to express as plain JSON expected-output rules.
      class VmPauseResume < DynamicTest
        def execute_test_steps(_test, result)
          assert_status!(result, 'running', 'before pause')

          execute_and_record(qmp_command('stop', desc: 'QMP: stop (pause) the VM'), result)
          assert_status!(result, 'paused', 'while paused')

          execute_and_record(qmp_command('cont', desc: 'QMP: cont (resume) the VM'), result)
          assert_status!(result, 'running', 'after resume')

          execute_and_record(
            guest_run(
              "Write-Output 'PASS: guest alive after pause/resume'",
              desc: 'Verify guest is responsive after pause/resume',
              expected_output_contains: 'PASS:',
              timeout: 60
            ),
            result
          )
        end

        def run_cleanup(_test)
          return unless query_status_value == 'paused'

          @logger.warn('VM still paused after test; issuing QMP cont during cleanup')
          @step_handler.execute_step(qmp_command('cont', desc: 'QMP cleanup: resume VM'))
        rescue StandardError => e
          @logger.warn("vm_pause_resume cleanup could not resume VM: #{e.message}")
        end

        private

        def assert_status!(result, expected, label)
          step = qmp_command('query-status', desc: "QMP: query-status #{label}")
          response = primary_qmp_result(execute_raw_and_record(step, result), step)
          status = status_from(response)
          return if status == expected

          raise EngineError, "Expected VM status '#{expected}' #{label}, got '#{status.inspect}'"
        end

        def query_status_value
          step = qmp_command('query-status')
          status_from(primary_qmp_result(
                        @command_execution_manager.execute(step, replacement: @context.replacement_map),
                        step
                      ))
        end

        def status_from(response)
          response.is_a?(Hash) ? response['status'] : response
        end
      end
    end
  end
end
