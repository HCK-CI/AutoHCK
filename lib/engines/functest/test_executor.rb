# frozen_string_literal: true

module AutoHCK
  module Functest
    # Drives test execution: runs each test's steps in order, records pass/fail
    # per step and per test, runs cleanup regardless of outcome, and produces
    # a summary hash written to functest_results.json.
    class TestExecutor
      attr_reader :results, :context

      def test_results
        @results.map { |r| Models::TestResult.from_functest(r) }
      end

      RunContext = Struct.new(:clients, :tools, :command_execution_manager, keyword_init: true)

      # Parallel-step constraints; see docs/Functest-Engine.md for details.
      # Step types allowed inside a parallel branch.
      PARALLEL_ALLOWED_STEP_TYPES = %i[
        guest_run guest_run_file files_action host_run host_run_file qmp_command qmp_wait_event
      ].freeze

      # rubocop:disable Metrics/AbcSize
      def initialize(engine, run_context)
        @project = engine.project
        @extensions = engine.extensions
        @clients = run_context.clients
        @tools = run_context.tools
        @machine_names = run_context.clients.map(&:name)
        @logger = engine.project.logger
        @context = TestContext.new(engine.project, run_context.clients.first.replacement_map)
        @command_execution_manager = run_context.command_execution_manager
        @step_handler = StepHandler.new(@project, @command_execution_manager, @context,
                                        default_timeout: engine.default_timeout)
        @results = []
        @current_test = nil
        @created_tags = Set.new
      end
      # rubocop:enable Metrics/AbcSize

      def execute_test(test)
        log_section("Starting test: #{test.name}")
        @logger.info("Description: #{@context.substitute_variables(test.description)}") if test.description

        if @results.none? { |r| r[:name] == test.name }
          @results << empty_test_result(test.name, test.description, display_name: test.display_name)
        end
        record_test(test)
      end

      def execute_tests(tests)
        @logger.info("Executing #{tests.length} test(s)")
        @results += tests.map do |test|
          empty_test_result(test.name, test.description, display_name: test.display_name)
        end
        tests.each { |test| execute_test(test) }
        summary
      end

      def summary
        total = @results.length
        passed = @results.count { |r| r[:status] == 'passed' }
        failed = @results.count { |r| r[:status] == 'failed' }

        @logger.info('')
        log_section('TEST SUMMARY')
        @logger.info("Total:  #{total}")
        @logger.info("Passed: #{passed}")
        @logger.info("Failed: #{failed}")
        @logger.info('-' * 80)

        { total: total, passed: passed, failed: failed, results: @results }
      end

      private

      def empty_test_result(name, description, display_name: nil)
        { name: name, display_name: display_name, description: description,
          status: 'not_run', duration: 0, dump_path: nil }
      end

      def tests_stats
        total = @results.length
        passed = @results.count { |r| r[:status] == 'passed' }
        failed = @results.count { |r| r[:status] == 'failed' }

        { 'current' => @current_test, 'passed' => passed,
          'failed' => failed, 'inqueue' => total - passed - failed,
          'currentcount' => passed + failed + 1, 'total' => total }
      end

      def create_local_test_copy(test)
        test.deep_dup.tap do |test_local|
          test_local.add_auto_index
          test_local.apply_cycles_to_steps
        end
      end

      def record_test(test)
        start_time = Time.now
        test_name = test.name
        @current_test = test_name
        result = @results.find { |r| r[:name] == test_name }
        raise EngineError, "Result placeholder not found for #{test_name}" unless result

        result.merge!({ status: 'running', steps: [], start_time: start_time.utc.iso8601 })
        @project.generate_result_report
        test_local = create_local_test_copy(test)
        run_test_steps(test_local, result)
        result
      ensure
        finalize_result(result, test, start_time)
        @current_test = nil

        @project.update_test_stats(tests_stats)
      end

      def finalize_result(result, test, start_time)
        run_cleanup(test)
        begin
          run_extension_post_test_commands(test.name)
        rescue StandardError => e
          @logger.error("Extension post-test command failed: #{e.message}")
          result[:status] = 'failed'
          result[:error] = e.message
        end
        result[:dump_path] = collect_memory_dumps(test.name)
        end_time = Time.now
        result[:end_time] = end_time.utc.iso8601
        result[:duration] = end_time - start_time

        @results.find { |r| r[:name] == test.name }.merge!(result)
        save_result(result, test)
      end

      def save_result(result, test)
        r_name = "Result_#{test.safe_name}.json"
        File.write("#{@project.workspace_path}/#{r_name}", JSON.pretty_generate(result))
        @project.result_uploader.upload_file("#{@project.workspace_path}/#{r_name}", r_name)

        @project.generate_result_report
        @project.generate_junit
      end

      def run_test_steps(test, result)
        prepare_test_clients!(test)
        ensure_boot_state!(test)
        run_extension_pre_test_commands(test.name)
        run_pre_test_commands(test)
        execute_test_steps(test, result)
        save_snapshot_if_needed(test)
        result[:status] = 'passed'
        @logger.info("PASSED: #{test.name}")
      rescue StandardError => e
        result[:status] = 'failed'
        result[:error] = e.message
        @logger.error("FAILED: #{test.name} - #{e.message}")
      end

      # Sets CommandExecutionManager's default machines to this test's own
      # clients, then fails the test right away if any step (including
      # pre_test_commands, cleanup, and parallel branches) targets an
      # undeclared client or violates a parallel execution constraint.
      def prepare_test_clients!(test)
        raise EngineError, "Test '#{test.name}' has an empty clients list" if test.clients.empty?

        @command_execution_manager.scope_to_test(test.clients)
        validate_step_clients!(test)
        validate_parallel_blocks!(test)
      end

      def all_steps(test)
        test.pre_test_commands + test.test_steps + test.cleanup
      end

      def validate_step_clients!(test)
        all_steps(test).each do |step|
          validate_single_step_clients!(step, test)
          next unless step.parallel

          step.parallel.branches.each_value do |branch_steps|
            branch_steps.each { |sub_step| validate_single_step_clients!(sub_step, test) }
          end
        end
      end

      def validate_single_step_clients!(step, test)
        unknown = step.clients - test.clients
        return if unknown.empty?

        raise EngineError, "Test '#{test.name}' step targets client(s) #{unknown.join(', ')} not declared " \
                           "in this test case's own clients list (#{test.clients.join(', ')})"
      end

      def validate_parallel_blocks!(test)
        all_steps(test).each do |step|
          validate_parallel_block!(step, test) if step.parallel
        end
      end

      def validate_parallel_block!(step, test)
        branches = step.parallel.branches
        raise EngineError, "Test '#{test.name}': parallel step '#{step.desc}' has no branches" if branches.empty?
        if branches.length < 2
          raise EngineError, "Test '#{test.name}': parallel step '#{step.desc}' must have at least two branches"
        end

        validate_no_conflicting_action!(step)
        validate_no_nested_parallel!(step, branches)
        validate_allowed_step_types!(step, branches)
        validate_no_client_overlap!(step, branches, test)
        validate_unique_capture_output!(step, branches)
      end

      def validate_no_conflicting_action!(step)
        fields = CommandExecutionManager::STEP_TYPE_FIELDS - [:parallel]
        active = fields.select { |field| step.step_type_active?(field) }
        return if active.empty?

        raise EngineError, "Step '#{step.desc}': 'parallel' cannot be combined with other step type " \
                           "field(s): #{active.join(', ')}"
      end

      def validate_no_nested_parallel!(step, branches)
        branches.each do |branch_name, branch_steps|
          next unless branch_steps.any?(&:parallel)

          raise EngineError, "Parallel step '#{step.desc}': branch '#{branch_name}' contains a nested " \
                             'parallel block, which is not supported'
        end
      end

      def validate_allowed_step_types!(step, branches)
        branches.each do |branch_name, branch_steps|
          branch_steps.each do |sub_step|
            active = CommandExecutionManager::STEP_TYPE_FIELDS.select { |field| sub_step.step_type_active?(field) }
            unless active.one?
              raise EngineError, "Parallel step '#{step.desc}': branch '#{branch_name}' step must contain " \
                                 "exactly one step type (found: #{active.join(', ')})"
            end

            disallowed = active - PARALLEL_ALLOWED_STEP_TYPES
            next if disallowed.empty?

            raise EngineError, "Parallel step '#{step.desc}': branch '#{branch_name}' contains a forbidden " \
                               "step type (#{disallowed.join(', ')} not allowed inside parallel branches)"
          end
        end
      end

      def validate_no_client_overlap!(step, branches, test)
        owner_by_client = {}
        branches.each do |branch_name, branch_steps|
          client_ids = branch_steps.flat_map { |sub_step| guest_targeted_clients(sub_step, test) }.uniq
          raise_client_overlap!(step, branch_name, client_ids, owner_by_client)
          client_ids.each { |client_id| owner_by_client[client_id] = branch_name }
        end
      end

      def raise_client_overlap!(step, branch_name, client_ids, owner_by_client)
        overlap = client_ids.select { |client_id| owner_by_client.key?(client_id) }
        return if overlap.empty?

        conflicts = overlap.map { |client_id| "#{client_id} (branch '#{owner_by_client[client_id]}')" }.join(', ')
        raise EngineError, "Parallel step '#{step.desc}': branch '#{branch_name}' targets client(s) already " \
                           "targeted by another branch in the same parallel step: #{conflicts}"
      end

      # Host-only steps target no client. An empty `clients` list broadcasts
      # to every client declared for the test, same as
      # CommandExecutionManager's own default.
      def guest_targeted_clients(sub_step, test)
        return [] unless sub_step.guest_run || sub_step.guest_run_file || sub_step.files_action.any? ||
                         sub_step.qmp_command || sub_step.qmp_wait_event

        sub_step.clients.empty? ? test.clients : sub_step.clients
      end

      # Rejects a capture_output name only when two *different* branches own
      # it; the same branch reusing a name across its own sequential steps
      # (last write wins) is normal and not a race.
      def validate_unique_capture_output!(step, branches)
        duplicates = capture_output_owners(branches).select { |_name, owners| owners.length > 1 }.keys
        return if duplicates.empty?

        raise EngineError, "Parallel step '#{step.desc}': duplicate capture_output variable name(s) " \
                           "across branches: #{duplicates.join(', ')}"
      end

      # Maps each capture_output name to the set of branches that use it.
      def capture_output_owners(branches)
        owners_by_name = Hash.new { |hash, name| hash[name] = Set.new }
        branches.each do |branch_name, branch_steps|
          branch_steps.filter_map(&:capture_output).each { |name| owners_by_name[name] << branch_name }
        end
        owners_by_name
      end

      def execute_test_steps(test, result)
        test.test_steps.each_with_index { |step, index| result[:steps] << execute_test_step(step, index) }
      end

      # Boots the VM into the state this test needs, if any. With neither
      # field set, nothing happens and the VM stays as-is.
      def ensure_boot_state!(test)
        if test.clean_boot && test.boot_from_snapshot_tag
          raise EngineError, "#{test.name}: clean_boot and boot_from_snapshot_tag are mutually exclusive"
        end

        client = @clients.first
        if test.clean_boot
          client.reboot_clean
        elsif test.boot_from_snapshot_tag
          ensure_tag_known!(test.boot_from_snapshot_tag, test.name)
          client.reboot_from_snapshot(test.boot_from_snapshot_tag)
        end
      end

      # A tag can only be used once the test that saved it (save_snapshot_as) has run.
      def ensure_tag_known!(tag, test_name)
        return if @created_tags.include?(tag)

        raise EngineError, "#{test_name}: boot_from_snapshot_tag references unknown tag '#{tag}' " \
                           '(the test that creates it via save_snapshot_as must run earlier in the suite)'
      end

      def save_snapshot_if_needed(test)
        tag = test.save_snapshot_as
        return unless tag

        if @created_tags.include?(tag)
          raise EngineError, "#{test.name}: snapshot tag '#{tag}' was already created by an earlier test"
        end

        @clients.first.save_snapshot(tag)
        @created_tags << tag
      end

      def execute_test_step(step, index)
        desc = @context.substitute_variables(step.desc)
        start_time = Time.now
        step_result = { index: index, description: desc, status: 'running', start_time: start_time.utc.iso8601 }
        run_step(step, index, step_result, desc)
        step_result
      ensure
        end_time = Time.now
        step_result[:end_time] = end_time.utc.iso8601
        step_result[:duration] = end_time - start_time
      end

      def run_step(step, index, step_result, desc)
        @step_handler.execute_step(step, index)
        step_result[:status] = 'passed'
        @logger.info("  PASS: #{desc}")
      rescue StandardError => e
        step_result[:status] = 'failed'
        step_result[:error] = e.message
        @logger.error("  FAIL: #{desc} - #{e.message}")
        raise
      ensure
        branch_results = @step_handler.last_branch_results
        step_result[:branches] = branch_results if branch_results
      end

      def log_section(title)
        @logger.info('=' * 80)
        @logger.info(title)
        @logger.info('=' * 80)
      end

      def run_pre_test_commands(test)
        return if test.pre_test_commands.empty?

        @logger.info('Running pre-test commands...')
        desc = nil
        test.pre_test_commands.each_with_index do |step, index|
          desc = @context.substitute_variables(step.desc)
          @step_handler.execute_step(step, index)
        rescue StandardError => e
          @logger.error("  FAIL: Pre-test command failed (#{desc}): #{e.message}")
          raise
        end
      end

      def run_cleanup(test)
        return if test.cleanup.empty?

        @logger.info('Running cleanup steps...')
        test.cleanup.each_with_index do |step, index|
          @step_handler.execute_step(step, index)
        rescue StandardError => e
          @logger.warn("Cleanup step failed (ignoring): #{e.message}")
        end
      end

      def collect_memory_dumps(test_name)
        id = test_name.gsub(/\W/, '_')
        MemoryDumpCollector.new(@tools, @machine_names, @project.workspace_path, @logger).collect(id)
      end

      def extension_commands_for(test_name, type)
        @extension_test_regexes ||= {}
        @extensions.flat_map(&:tests_config).select do |config|
          regex = (@extension_test_regexes[config] ||= Regexp.union(config.tests.map { Regexp.new(_1) }))
          regex.match?(test_name)
        end.flat_map(&type)
      end

      def run_extension_pre_test_commands(test_name)
        cmds = extension_commands_for(test_name, :pre_test_commands)
        return if cmds.empty?

        @logger.info('Running extension pre-test commands...')
        cmds.each_with_index do |step, index|
          desc = @context.substitute_variables("[Extension pre-test step #{index + 1}] #{step.desc}")
          @step_handler.execute_step(step, index)
        rescue StandardError => e
          @logger.error("  FAIL: Extension pre-test command failed (#{desc}): #{e.message}")
          raise
        end
      end

      def run_extension_post_test_commands(test_name)
        cmds = extension_commands_for(test_name, :post_test_commands)
        return if cmds.empty?

        @logger.info('Running extension post-test commands...')
        cmds.each_with_index do |step, index|
          desc = @context.substitute_variables("[Extension post-test step #{index + 1}] #{step.desc}")
          @step_handler.execute_step(step, index)
        rescue StandardError => e
          @logger.error("  FAIL: Extension post-test command failed (#{desc}): #{e.message}")
          raise
        end
      end
    end
  end
end
