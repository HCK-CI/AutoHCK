# frozen_string_literal: true

module AutoHCK
  module Functest
    # Runs the branches of one `parallel` step at the same time, each fully
    # isolated from the others until they've all finished. Captured
    # variables only become visible to the rest of the test once every
    # branch is done. See ParallelBlock#fail_fast for cancellation rules.
    class ParallelBranchRunner
      # branch_name => { status:, steps: [{ index:, description:, status:,
      # start_time:, end_time:, duration:, error: }] }
      attr_reader :branch_results

      # A branch's identity
      Branch = Struct.new(:name, :context, keyword_init: true)

      def initialize(project, command_execution_manager, context, logger, default_timeout)
        @project = project
        @command_execution_manager = command_execution_manager
        @context = context
        @logger = logger
        @default_timeout = default_timeout
      end

      # rubocop:disable Metrics/AbcSize
      def run(step)
        branches = step.parallel.branches
        @logger.info("Starting parallel block (branches: #{branches.keys.join(', ')})")

        state = new_run_state
        @branch_results = state[:branch_results]
        threads = start_branch_threads(branches, step.parallel.fail_fast, state)
        threads.each_value(&:join)

        apply_captured_variables(state[:captures])
        raise_first_failure(state[:errors], branches.keys)

        @logger.info("Parallel block completed (branches: #{branches.keys.join(', ')})")
      ensure
        kill_lingering_threads(threads, state)
      end
      # rubocop:enable Metrics/AbcSize

      private

      # State shared by every branch for the duration of one #run call.
      def new_run_state
        { cancelled: false, mutex: Mutex.new, captures: {}, errors: {}, branch_results: {} }
      end

      # Stops any branches already started if starting another one fails,
      # instead of leaving them running unsupervised. Keyed by branch name
      # so a later force-kill can tell which branch a thread belongs to.
      def start_branch_threads(branches, fail_fast, state)
        threads = {}
        branches.each do |branch_name, branch_steps|
          threads[branch_name] = Thread.new { run_branch(branch_name, branch_steps, fail_fast, state) }
        end
        threads
      rescue StandardError
        kill_lingering_threads(threads, state)
        raise
      end

      # Runs one branch's steps sequentially; stops early on its own
      # failure or when another branch's failure cancels the block.
      def run_branch(branch_name, branch_steps, fail_fast, state)
        step_results = []
        branch, branch_handler = start_branch(branch_name, step_results, state)

        branch_steps.each_with_index do |sub_step, index|
          break if fail_fast && cancelled?(state)

          step_result = execute_branch_step(branch_handler, branch, sub_step, index)
          step_results << step_result
          break if step_result[:status] == 'failed'
        end

        finish_branch(branch, branch_steps.length, step_results, fail_fast, state)
      rescue StandardError => e
        record_branch_results(branch_name, 'failed', step_results, state)
        record_branch_failure(branch_name, e.message, fail_fast, state)
      end

      # Sets up one branch's isolated context and step handler. Also records
      # a 'running' placeholder up front so a forced kill (see
      # #kill_lingering_threads) still has a `steps` array to report, filled
      # in as steps finish.
      def start_branch(branch_name, step_results, state)
        record_branch_results(branch_name, 'running', step_results, state)
        branch = Branch.new(name: branch_name, context: BranchContext.new(@context))
        branch_handler = StepHandler.new(@project, @command_execution_manager, branch.context,
                                         default_timeout: @default_timeout)
        [branch, branch_handler]
      end

      # Runs and times one sub-step, turning a failure into a step result
      # instead of raising.
      def execute_branch_step(branch_handler, branch, sub_step, index)
        desc = branch.context.substitute_variables(sub_step.desc)
        start_time = Time.now
        status, error = run_sub_step(branch_handler, branch.name, sub_step, desc)
        end_time = Time.now

        { index: index, description: desc, status: status, error: error, start_time: start_time.utc.iso8601,
          end_time: end_time.utc.iso8601, duration: end_time - start_time }.compact
      end

      # Runs one sub-step, turning a failure into a [status, error message]
      # pair instead of raising.
      def run_sub_step(branch_handler, branch_name, sub_step, desc)
        branch_handler.execute_step(sub_step)
        @logger.info("  [#{branch_name}] PASS: #{desc}")
        ['passed', nil]
      rescue StandardError => e
        @logger.error("  [#{branch_name}] FAIL: #{desc} - #{e.message}")
        ['failed', e.message]
      end

      # Determines the branch's final status and, if it succeeded, hands
      # off its captured variables to be shared with the rest of the test.
      def finish_branch(branch, total_steps, step_results, fail_fast, state)
        branch_name = branch.name
        failed_step = step_results.find { |step_result| step_result[:status] == 'failed' }
        status = branch_status(failed_step, step_results, total_steps)
        record_branch_results(branch_name, status, step_results, state)

        if failed_step
          record_branch_failure(branch_name, failed_step[:error], fail_fast, state)
          return
        end

        if status == 'cancelled'
          @logger.warn("Parallel branch '#{branch_name}' cancelled")
        else
          @logger.info("Parallel branch '#{branch_name}' passed")
        end

        state[:mutex].synchronize { state[:captures][branch_name] = branch.context.pending_captures }
      end

      # 'cancelled': stopped early because another branch failed (fail_fast).
      def branch_status(failed_step, step_results, total_steps)
        return 'failed' if failed_step
        return 'cancelled' if step_results.length < total_steps

        'passed'
      end

      def record_branch_results(branch_name, status, step_results, state)
        state[:mutex].synchronize { state[:branch_results][branch_name] = { status: status, steps: step_results } }
      end

      # Logs the failure and, for fail_fast blocks, signals every other
      # branch to stop.
      def record_branch_failure(branch_name, error_message, fail_fast, state)
        @logger.error("Parallel branch '#{branch_name}' failed: #{error_message}")
        state[:mutex].synchronize do
          state[:errors][branch_name] = error_message
          state[:cancelled] = true if fail_fast
        end
      end

      def cancelled?(state)
        state[:mutex].synchronize { state[:cancelled] }
      end

      # Shares every successful branch's captured variables with the rest
      # of the test. Failed branches never reach here, since they never
      # hand off captures in the first place.
      def apply_captured_variables(captures_by_branch)
        captures_by_branch.each_value do |captures|
          captures.each { |name, value| @context.set_variable(name, value) }
        end
      end

      # Surfaces the first failure by branch declaration order
      def raise_first_failure(errors, branch_declaration_order)
        return if errors.empty?

        first_name = branch_declaration_order.find { |name| errors.key?(name) }
        other_names = errors.keys - [first_name]
        message = "Parallel branch '#{first_name}' failed: #{errors[first_name]}"
        message += "; also failed: #{other_names.join(', ')}" unless other_names.empty?

        raise EngineError, message
      end

      # Force-stops any branch still running after a timeout or abort. A
      # killed thread never reaches finish_branch on its own, so this also
      # finalizes its result instead of leaving it missing from the report.
      def kill_lingering_threads(threads, state)
        return if threads.nil?

        threads.each do |branch_name, thread|
          next unless thread.alive?

          @logger.warn("Killing a still-running parallel branch thread (outer timeout or abort): #{branch_name}")
          thread.kill
          thread.join(5)
          finalize_killed_branch(branch_name, state)
        end
      end

      # Turns the 'running' placeholder (see #run_branch) into a terminal
      # status, keeping whatever steps it managed to finish beforehand.
      def finalize_killed_branch(branch_name, state)
        state[:mutex].synchronize do
          result = state[:branch_results][branch_name]
          result[:status] = 'timeout' if result && result[:status] == 'running'
        end
      end
    end
  end
end
