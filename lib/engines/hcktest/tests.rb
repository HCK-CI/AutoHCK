# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Tests class
  class Tests
    extend T::Sig
    include Helper
    attr_reader :tests

    HANDLE_TESTS_POLLING_INTERVAL = 60
    APPLYING_FILTERS_INTERVAL = 50
    VERIFY_TARGET_RETRIES = 5
    VERIFY_TARGET_SLEEP = 5
    QUEUE_TEST_TIMEOUT = '00:15:00'
    RUNNING_TEST_TIMEOUT = '00:15:00'
    SUMMARY_LOG_FILE = 'logs.txt'
    RESULTS_FILE = 'results.html'
    RESULTS_YAML = 'results.yaml'
    RESULTS_REPORT_SECTIONS = %w[chart guest_info rejected_test url].freeze

    def initialize(client, support, project, target, tools)
      @client = client
      @project = project
      @tag = project.engine_tag
      @target = target
      @tools = tools
      @support = support
      @logger = project.logger
      @playlist = Playlist.new(client, project, target, tools, @client.kit)
      @tests = T.let([], T::Array[Models::HLK::Test])
      @test_results = []
      @results_template = ERB.new(File.read('lib/templates/report.html.erb'))
    end

    sig { params(updated_tests: T::Array[Models::HLK::Test]).returns(T::Array[Models::HLK::Test]) }
    def merge_tests_update(updated_tests)
      # Initial load of tests, no extra information
      return @tests = updated_tests if @tests.empty?

      @tests.each do |test|
        updated_test = updated_tests.find { _1.id == test.id }
        # This should not happen, but to make Sorbet happy
        raise(EngineError, "Test not found: #{test.id}") if updated_test.nil?

        test.update_from_hck(updated_test)
      end
    end

    sig { returns(T::Array[Models::HLK::Test]) }
    def rejected_tests
      @playlist.rejected_test
    end

    sig { params(log: T::Boolean).returns(T::Array[Models::HLK::Test]) }
    def update_tests(log: false)
      retries = 0
      begin
        last_done_test_results = done_test_results
        @test_results = @tools.list_all_results(@target['key'], @client.name, @tag)
        @new_done_test_results = done_test_results - last_done_test_results

        merge_tests_update(@playlist.list_tests(log))
      rescue Playlist::ListTestsError => e
        @logger.warn(e.message)
        @logger.info('Reconnecting tools...')
        @tools.reconnect
        raise unless (retries += 1) == 1 || verify_target

        @logger.info('Trying again to list tests')
        retry
      end
    end

    def verify_target
      retries = 0
      begin
        @logger.info('Verifying target...')
        target = Targets.new(@client, @project, @tools, @tag).search_target
        return false if target.eql?(@target)

        @logger.info('Target changed, updating...')
        @target = target
        @playlist.update_target(target)
        true
      rescue Targets::SearchTargetError => e
        @logger.warn(e.message)
        raise unless (retries += 1) < VERIFY_TARGET_RETRIES

        sleep VERIFY_TARGET_SLEEP
        @logger.info('Trying again to verify target')
        retry
      end
    end

    sig { params(test: Models::HLK::Test).returns(T::Boolean) }
    def support_needed?(test)
      (test.scheduleoptions & %w[6 RequiresMultipleMachines]) != []
    end

    def test_support(test)
      @support.name if support_needed?(test)
    end

    sig { params(test: Models::HLK::Test, status: String).void }
    def set_test_status(test, status)
      return if test.ex_status == status

      test.ex_status = status
      update_summary_results_log
    end

    def check_test_queued_time
      # We can't compare test objects directly because the list_tests
      # function updates the test object but the current_test function
      # returns the pure object.
      @logger.debug("Checking queued time for test id: #{@last_queued_test&.id}. Current test: #{current_test}")

      # When @last_queued_test is nil then all queued tests are running or finished
      return if @last_queued_test.nil?

      @logger.debug("Test extra information: #{@last_queued_test.extra}")

      # When 'started_at' is not nil then last queued test is running or finished
      return unless @last_queued_test.started_at.nil?

      diff = time_diff(@last_queued_test.queued_at, DateTime.now)

      return if diff < time_to_seconds(QUEUE_TEST_TIMEOUT)

      @logger.warn("Test was queued #{seconds_to_time(diff)} ago! HCK hangs on?")
      set_test_status(@last_queued_test, 'Hangs on at queued state?')
    end

    def check_test_duration_time
      return if (test = current_test).nil?

      started_at = test.started_at

      return if started_at.nil?

      diff = time_diff(started_at, DateTime.now)

      return if diff < (2 * test.duration) + time_to_seconds(RUNNING_TEST_TIMEOUT)

      @logger.warn("Test was running #{seconds_to_time(diff)} ago! HCK hangs on?")
      set_test_status(test, 'Hangs on at running state?')
    end

    def wait_queued_test(id)
      loop do
        sleep 5
        results = @tools.list_test_results(id, @target['key'], @client.name, @tag)
        last_result = results.max_by { |k| k['instanceid'].to_i }

        check_test_queued_time

        break if last_result['status'] == 'InQueue'
        break if last_result['status'] == 'Running'
        break if test_result_finished?(last_result)
      end
    end

    def select_test_config(test_name, config)
      tests_config = @project.engine.config.tests_config + @project.engine.drivers.flat_map(&:tests_config)

      tests_config
        .select { |test_config| Regexp.union(test_config.tests.map { Regexp.new(_1) }).match?(test_name) }
        .flat_map(&config)
    end

    def test_parameters(test_name)
      select_test_config(test_name, :parameters)
        .to_h { |parameter| [parameter.name, parameter.value] }
    end

    def run_command_on_client(client, command, desc)
      @logger.info("Running command (#{desc}) on client #{client.name}")
      @tools.run_on_machine(client.name, desc, command)
    end

    sig { params(test: Models::HLK::Test, type: Symbol).void }
    def run_test_commands(test, type)
      select_test_config(test.name, type).each do |command|
        guest_cmd = command.guest_run
        desc = command.desc
        if guest_cmd
          run_command_on_client(@client, guest_cmd, desc)
          run_command_on_client(@support, guest_cmd, desc) unless @support.nil?
        end

        next unless command.host_run

        @logger.info("Running command (#{desc}) on host")
        run_cmd(command.host_run)
      end
    end

    sig { params(test: Models::HLK::Test, wait: T::Boolean).void }
    def queue_test(test, wait: false)
      @tools.queue_test(test_id: test.id,
                        target_key: @target['key'],
                        machine: @client.name,
                        tag: @tag,
                        support: test_support(test),
                        parameters: test_parameters(test.name))

      test.queued_at = DateTime.now

      @last_queued_test = test

      return unless wait

      wait_queued_test(test.id)
    end

    sig { returns(T.nilable(Models::HLK::Test)) }
    def current_test
      @tests.find { |test| test.executionstate == Models::HLK::ExecutionState::Running }
    end

    def tests_stats
      cnt_passed = tests_stats_status_count(Models::HLK::TestResultStatus::Passed)
      cnt_failed = tests_stats_status_count(Models::HLK::TestResultStatus::Failed)
      total = @tests.count

      { 'current' => current_test, 'passed' => cnt_passed,
        'failed' => cnt_failed, 'inqueue' => total - cnt_passed - cnt_failed,
        'skipped' => @playlist.rejected_test.count,
        'currentcount' => cnt_passed + cnt_failed + 1, 'total' => total }
    end

    def test_result_finished?(result)
      %w[Passed Failed].include? result['status']
    end

    sig { params(status: Models::HLK::TestResultStatus).returns(Integer) }
    def tests_stats_status_count(status)
      # When test is running more than once HLK reports test['status'] = PASS/FAIL
      # even when test is still running again. So we need to check test['executionstate']
      # to be sure that test is really finished.
      # Otherwise update_tests function can report test as finished multiple times
      # just with different executionstate.
      @tests.count { |test| test.status == status && test.executionstate == Models::HLK::ExecutionState::NotRunning }
    end

    def done_test_results
      @test_results.select { |test_result| test_result_finished?(test_result) }
    end

    sig { params(test: Models::HLK::Test).void }
    def on_test_start(test)
      @logger.info(">>> Currently running: #{test.name} [#{test.estimatedruntime}]")

      test.started_at = DateTime.now
      test.ex_status = nil

      update_summary_results_log
    end

    def print_tests_stats
      stats = tests_stats
      @logger.info("<<< Passed: #{stats['passed']} | Failed: #{stats['failed']} | InQueue: #{stats['inqueue']}")
    end

    sig { params(test: Models::HLK::Test, test_result: T::Hash[String, T.untyped]).void }
    def print_test_results(test, test_result)
      @logger.info("#{test_result['status']}: #{test.name}")
      @logger.info("Test information page: #{test.url}")
    end

    sig { params(test: Models::HLK::Test, test_result: T::Hash[String, T.untyped]).void }
    def archive_test_results(test, test_result)
      res = @tools.zip_test_result_logs(result_index: test_result['instanceid'],
                                        test: test.id,
                                        target: @target['key'],
                                        project: @tag,
                                        machine: @client.name,
                                        pool: @tag,
                                        index_instance_id: true)
      @logger.info('Test archive successfully created')
    rescue Tools::ZipTestResultLogsError
      @logger.info('Skipping archiving test result logs')
    ensure
      update_remote(test, test_result, res&.dig('hostlogszippath'), test_result['status'], test.safe_name)
      @logger.info('Test results uploaded via the result uploader')
    end

    def report_data
      {
        'tag' => @tag,
        'test_stats' => tests_stats,
        'rejected_test' => @playlist.rejected_test,
        'tests' => @tests,
        'url' => @project.result_uploader.url,
        'system_info' => {
          'guest' => @clients_system_info
        },
        'sections' => RESULTS_REPORT_SECTIONS - @project.options.test.reject_report_sections
      }
    end

    def generate_report
      data = report_data

      results_file = "#{@project.workspace_path}/#{RESULTS_FILE}"
      results_yaml = "#{@project.workspace_path}/#{RESULTS_YAML}"

      File.write(results_file, @results_template.result_with_hash(data))
      @project.result_uploader.delete_file(RESULTS_FILE)
      @project.result_uploader.upload_file(results_file, RESULTS_FILE)

      File.write(results_yaml, data.to_yaml)
      @project.result_uploader.delete_file(RESULTS_YAML)
      @project.result_uploader.upload_file(results_yaml, RESULTS_YAML)
    end

    def summary_rejected_test_log
      @playlist.rejected_test.reduce('') do |sum, test|
        sum + "Skipped: #{test.name} [#{test.estimatedruntime}]\n"
      end
    end

    def summary_results_log
      @tests.reduce('') do |sum, test|
        extra_info = test.dump_path ? '(with Minidump)' : ''
        status = test.ex_status || test.status

        sum + "#{status}: #{test.name} [#{test.estimatedruntime}]#{extra_info}#{format_times(test)}\n"
      end
    end

    sig { params(test: Models::HLK::Test).returns(String) }
    def format_times(test)
      queued_at = test.queued_at
      queued_at_str = queued_at ? " [Queued time: #{queued_at}]" : ''
      started_at = test.started_at
      started_at_str = started_at ? " [Started time: #{started_at}]" : ''
      finished_at = test.finished_at
      finished_at_str = finished_at ? " [Finished time: #{finished_at}]" : ''

      "#{queued_at_str}#{started_at_str}#{finished_at_str}"
    end

    def update_summary_results_log
      logs = summary_rejected_test_log
      logs += summary_results_log

      @logger.info('Tests results logs updated via the result uploader')
      @project.result_uploader.update_file_content(logs, SUMMARY_LOG_FILE)
      File.write("#{@project.workspace_path}/#{SUMMARY_LOG_FILE}", logs)

      generate_report
    end

    sig do
      params(test: Models::HLK::Test,
             test_result: T::Hash[String, T.untyped],
             test_logs_path: T.nilable(String),
             status: String,
             testname: String).void
    end
    def update_remote(test, test_result, test_logs_path, status, testname)
      test_instance_id = test_result['instanceid']
      delete_old_remote(testname, test_instance_id)

      if test_logs_path
        r_name = "#{status}_#{test_instance_id}_#{testname}#{File.extname(test_logs_path)}"
        @project.result_uploader.upload_file(test_logs_path, r_name)
      end

      r_name = "Result_#{test_instance_id}_#{testname}.json"
      File.write("#{@project.workspace_path}/#{r_name}", JSON.pretty_generate(test_result))
      @project.result_uploader.upload_file("#{@project.workspace_path}/#{r_name}", r_name)

      if test.dump_path
        r_name = "Minidump_#{test_instance_id}_#{testname}.zip"
        @project.result_uploader.upload_file(test.dump_path, r_name)
      end

      update_summary_results_log
    end

    def delete_old_remote(test_name, result_instance_id)
      r_name = "Minidump_#{result_instance_id}_#{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
      r_name = "Result_#{result_instance_id}_#{test_name}.json"
      @project.result_uploader.delete_file(r_name)
      r_name = "Failed_#{result_instance_id}_#{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
      r_name = "Passed_#{result_instance_id}_#{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
    end

    def all_tests_finished?
      # When the test runs several times:
      # Test 'status' changed to 'Passed/Failed' just after the test 'executionstate'
      # moved from 'InQueue' to 'Running'
      # Test 'executionstate' moves from 'Running' to 'NotRunning' just after the main
      # part of the test is finished even if the cleanup stage is still running
      # As a result `@new_done_test_results = []`, because test result `status` is
      # not 'Passed/Failed' yet.

      @tests.none? { _1.status == Models::HLK::TestResultStatus::InQueue } &&
        # TestResult.Status does not return Queued
        # (if a test is scheduled or running it returns Running).
        @test_results.none? { _1['status'] == 'Running' } &&
        current_test.nil?
    end

    def download_memory_dump(machine, l_tmp_path)
      exist = @tools.exists_on_machine?(machine, '${env:SystemRoot}/Minidump')
      @logger.debug("Checking Minidump exist on #{machine}: #{exist}")
      return false unless exist

      @logger.info("Downloading memory dump (Minidump) from #{machine}")
      @tools.download_from_machine(machine, '${env:SystemRoot}/Minidump', l_tmp_path)
      @tools.delete_on_machine(machine, '${env:SystemRoot}/Minidump')

      true
    end

    def download_memory_dumps(l_tmp_path)
      downloaded_client = download_memory_dump(@client.name, "#{l_tmp_path}/#{@client.name}_#{current_timestamp}")
      unless @support.nil?
        downloaded_support = download_memory_dump(@support.name,
                                                  "#{l_tmp_path}/#{@support.name}_#{current_timestamp}")
      end

      downloaded_client || downloaded_support
    end

    sig { params(test: Models::HLK::Test).void }
    def collect_memory_dumps(test)
      l_zip_path = "#{@project.workspace_path}/memory_dump_#{test.id}.zip"
      l_tmp_path = "#{@project.workspace_path}/tmp_#{test.id}"

      if download_memory_dumps(l_tmp_path)
        create_zip_from_directory(l_zip_path, l_tmp_path)
        test.dump_path = l_zip_path
      end

      FileUtils.rm_rf(l_tmp_path)
    end

    sig { params(test: Models::HLK::Test, test_result: T::Hash[String, T.untyped]).void }
    def handle_finished_test_result(test, test_result)
      collect_memory_dumps(test)

      print_test_results(test, test_result)
      archive_test_results(test, test_result)

      test.finished_at = DateTime.now
      test.last_result = test_result
    end

    sig { params(result: T::Hash[String, T.untyped]).returns(Models::HLK::Test) }
    def test_for_result(result)
      test = @tests.find { |test| test.name == result['name'] }

      raise "Test not found for result: #{result}" if test.nil?

      test
    end

    def handle_finished_test_results(results)
      @project.update_test_stats(tests_stats)

      results.each do |result|
        test = test_for_result(result)
        next if test.nil?

        test.ex_status = nil
        handle_finished_test_result(test, result)

        @last_queued_test = nil if test.id == @last_queued_test&.id
      end
      print_tests_stats
    end

    def reset_clients_to_ready_state
      @client.reset_to_ready_state
      @support&.reset_to_ready_state
    end

    def apply_filters
      @logger.info('Applying filters on finished tests')
      @tools.apply_project_filters(@tag)
      sleep APPLYING_FILTERS_INTERVAL
    end

    def check_new_finished_results
      return unless @new_done_test_results.any?

      apply_filters
      handle_finished_test_results(@new_done_test_results)
    end

    def handle_test_running
      running = T.let(nil, T.nilable(Models::HLK::Test))

      until @project.run_terminated
        @project.check_run_termination
        # Update tests results to get the latest status of the tests
        update_tests
        reset_clients_to_ready_state
        check_new_finished_results
        check_test_queued_time
        check_test_duration_time
        if current_test != running
          running = current_test
          on_test_start(running) if running
        end
        break if all_tests_finished?

        sleep HANDLE_TESTS_POLLING_INTERVAL
      end
    end

    def create_project_package
      package_playlist = @playlist.playlist if @project.options.test.package_with_playlist

      res = @tools.create_project_package(@tag, package_playlist)
      @logger.info('Results package successfully created')
      r_name = @tag + File.extname(res['hostprojectpackagepath'])
      @project.result_uploader.upload_file(res['hostprojectpackagepath'], r_name)
    end

    def build_system_info(info)
      @clients_system_info ||= {}

      system_info = {
        'Host' => info['Host Name'],
        'OS' => "#{info['OS Name']} #{info['OS Version']}",
        'System' => "#{info['System Manufacturer']} #{info['System Model']} #{info['System Type']}",
        'CPU' => info['Processor(s)'].join(' '),
        'Memory' => info['Total Physical Memory'],
        'BIOS' => info['BIOS Version']
      }

      @clients_system_info[info['Host Name']] = system_info
    end

    def load_clients_system_info
      parser = SysInfoParser.new

      client_sysinfo = parser.parse(@tools.get_machine_system_info(@client.name))
      build_system_info(client_sysinfo)

      return if @support.nil?

      support_sysinfo = parser.parse(@tools.get_machine_system_info(@support.name))
      build_system_info(support_sysinfo)
    end

    sig { params(tests: T::Array[Models::HLK::Test]).void }
    def run(tests)
      load_clients_system_info
      update_summary_results_log
      tests.each do |test|
        run_test_commands(test, :pre_test_commands)
        run_count = test.run_count

        (1..run_count).each do |run_number|
          test_str = "run #{run_number}/#{run_count} #{test.name} (#{test.id})"
          @logger.info("Adding to queue: #{test_str}")
          queue_test(test, wait: true)
          handle_test_running
          @project.generate_junit

          break if @project.run_terminated
        end

        run_test_commands(test, :post_test_commands)

        break if @project.run_terminated
      end
    end
  end
end
