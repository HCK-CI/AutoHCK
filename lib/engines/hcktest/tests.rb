# frozen_string_literal: true

require 'erb'
require 'date'
require 'fileutils'
require './lib/engines/hcktest/playlist'
require './lib/auxiliary/sysinfo_parser'
require './lib/auxiliary/time_helper'
require './lib/auxiliary/zip_helper'

# AutoHCK module
module AutoHCK
  # Tests class
  class Tests
    include Helper

    HANDLE_TESTS_POLLING_INTERVAL = 10
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
      @tag = project.engine.tag
      @target = target
      @tools = tools
      @support = support
      @logger = project.logger
      @playlist = Playlist.new(client, project, target, tools, @client.kit)
      @tests = []
      @tests_extra = {}

      @results_template = ERB.new(File.read('lib/templates/report.html.erb'))
    end

    def list_tests(log: false)
      retries ||= 0
      @tests = @playlist.list_tests(log)
    rescue Playlist::ListTestsError => e
      @logger.warn(e.message)
      @logger.info('Reconnecting tools...')
      @tools.reconnect
      raise unless (retries += 1) == 1 || verify_target

      @logger.info('Trying again to list tests')
      retry
    end

    def verify_target
      retries ||= 0
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

    def support_needed?(test)
      (test['scheduleoptions'] & %w[6 RequiresMultipleMachines]) != []
    end

    def test_support(test)
      @support.name if support_needed?(test)
    end

    def set_test_status(id, status)
      return if @tests_extra.dig(id, 'status') == status

      @tests_extra[id]['status'] = status
      update_summary_results_log
    end

    def check_test_queued_time
      # We can't compare test objects directly because the list_tests
      # function updates the test object but the current_test function
      # returns the pure object.

      @logger.debug("Checking queued time for test id: #{@last_queued_id}. Current test: #{current_test}")
      @logger.debug("Test extra information: #{@tests_extra[@last_queued_id]}")

      # When @last_queued_id is nil then all queued tests are running or finished
      return if @last_queued_id.nil?

      # When 'started_at' is not nil then last queued test is running or finished
      return unless @tests_extra[@last_queued_id]['started_at'].nil?

      diff = time_diff(@tests_extra[@last_queued_id]['queued_at'], DateTime.now)

      return if diff < time_to_seconds(QUEUE_TEST_TIMEOUT)

      @logger.warn("Test was queued #{seconds_to_time(diff)} ago! HCK hangs on?")
      set_test_status(@last_queued_id, 'Hangs on at queued state?')
    end

    def check_test_duration_time
      return if (test = current_test).nil?

      id = test['id']
      duration = test['duration']
      started_at = @tests_extra[id]['started_at']

      return if started_at.nil?

      diff = time_diff(started_at, DateTime.now)

      return if diff < (2 * duration) + time_to_seconds(RUNNING_TEST_TIMEOUT)

      @logger.warn("Test was running #{seconds_to_time(diff)} ago! HCK hangs on?")
      set_test_status(id, 'Hangs on at running state?')
    end

    def wait_queued_test(id)
      loop do
        sleep 5
        results = @tools.list_test_results(id, @target['key'], @client.name, @tag)
        last_result = results.max_by { |k| k['instanceid'].to_i }

        check_test_queued_time

        break if last_result['status'] == 'InQueue'
        break if last_result['status'] == 'Running'
        break if test_finished?(last_result)
      end
    end

    def queue_test(test, wait: false)
      @tools.queue_test(test['id'], @target['key'], @client.name, @tag,
                        test_support(test))

      @tests_extra[test['id']] ||= {}
      @tests_extra[test['id']]['queued_at'] = DateTime.now

      @last_queued_id = test['id']

      return unless wait

      wait_queued_test(test['id'])
    end

    def current_test
      @tests.find { |test| test['executionstate'] == 'Running' }
    end

    def status_count(status)
      @tests.count { |test| test['status'] == status }
    end

    def tests_stats
      cnt_passed = status_count('Passed')
      cnt_failed = status_count('Failed')

      { 'current' => current_test, 'passed' => cnt_passed,
        'failed' => cnt_failed, 'inqueue' => @total - cnt_passed - cnt_failed,
        'skipped' => @playlist.rejected_test.count,
        'currentcount' => done_tests.count + 1, 'total' => @total }
    end

    def test_finished?(test)
      %w[Passed Failed].include? test['status']
    end

    def done_tests
      @tests.select { |test| test_finished?(test) }
    end

    def on_test_start(test)
      @logger.info(">>> Currently running: #{test['name']} [#{test['estimatedruntime']}]")

      @tests_extra[test['id']]['started_at'] = DateTime.now
      @tests_extra[test['id']]['status'] = nil

      update_summary_results_log
    end

    def print_tests_stats
      stats = tests_stats
      @logger.info("<<< Passed: #{stats['passed']} | Failed: #{stats['failed']} | InQueue: #{stats['inqueue']}")
    end

    def print_test_results(test)
      results = @tests.find { |t| t['id'] == test['id'] }
      @logger.info("#{results['status']}: #{test['name']}")
      @logger.info("Test information page: #{test['url']}")
    end

    def archive_test_results(test)
      res = @tools.zip_test_result_logs(test['id'], @target['key'], @client.name,
                                        @tag)
      @logger.info('Test archive successfully created')
      update_remote(test['id'], res['hostlogszippath'], res['status'], res['testname'])
      @logger.info('Test archive uploaded via the result uploader')
    rescue Tools::ZipTestResultLogsError
      @logger.info('Skipping archiving test result logs')
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
        sum + "Skipped: #{test['name']} [#{test['estimatedruntime']}]\n"
      end
    end

    def summary_results_log
      @tests.reduce('') do |sum, test|
        extra_info = @tests_extra.dig(test['id'], 'dump') ? '(with Minidump)' : ''
        status = @tests_extra.dig(test['id'], 'status') || test['status']
        sum + "#{status}: #{test['name']} [#{test['estimatedruntime']}] #{extra_info}\n"
      end
    end

    def update_summary_results_log
      logs = summary_rejected_test_log
      logs += summary_results_log

      @logger.info('Tests results logs updated via the result uploader')
      @project.result_uploader.update_file_content(logs, SUMMARY_LOG_FILE)
      File.write("#{@project.workspace_path}/#{SUMMARY_LOG_FILE}", logs)

      generate_report
    end

    def update_remote(test_id, test_logs_path, status, testname)
      delete_old_remote(testname)
      new_filename = "#{status}: #{testname}"
      r_name = new_filename + File.extname(test_logs_path)
      @project.result_uploader.upload_file(test_logs_path, r_name)

      if @tests_extra.dig(test_id, 'dump')
        r_name = "Minidump: #{testname}.zip"
        @project.result_uploader.upload_file(@tests_extra.dig(test_id, 'dump'), r_name)
      end

      update_summary_results_log
    end

    def delete_old_remote(test_name)
      r_name = "Minidump: #{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
      r_name = "Failed: #{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
      r_name = "Passed: #{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
    end

    def all_tests_finished?
      status_count('InQueue').zero? && current_test.nil?
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

    def collect_memory_dumps(test)
      id = test['id']

      l_zip_path = "#{@project.workspace_path}/memory_dump_#{id}.zip"
      l_tmp_path = "#{@project.workspace_path}/tmp_#{id}"

      if download_memory_dumps(l_tmp_path)
        create_zip_from_directory(l_zip_path, l_tmp_path)
        @tests_extra[id]['dump'] = l_zip_path
      end

      FileUtils.rm_rf(l_tmp_path)
    end

    def handle_finished_tests(tests)
      tests.each do |test|
        @tests_extra[test['id']]['status'] = nil

        @project.github.update(tests_stats) if @project.github&.connected?

        collect_memory_dumps(test)

        print_test_results(test)
        archive_test_results(test)

        @last_queued_id = nil if test['id'] == @last_queued_id
      end
      print_tests_stats
    end

    def reset_clients_to_ready_state
      @client.reset_to_ready_state
      @support&.reset_to_ready_state
    end

    def new_done
      list_tests
      done_tests - @last_done
    end

    def apply_filters
      @logger.info('Applying filters on finished tests')
      @tools.apply_project_filters(@tag)
      sleep APPLYING_FILTERS_INTERVAL
    end

    def check_new_finished_tests
      return unless new_done.any?

      apply_filters
      handle_finished_tests(new_done)
    end

    def handle_test_running
      running = nil

      until all_tests_finished? || @project.run_terminated
        @project.check_run_termination
        reset_clients_to_ready_state
        check_new_finished_tests
        check_test_queued_time
        check_test_duration_time
        if current_test != running
          running = current_test
          on_test_start(running) if running
        end
        @last_done = done_tests
        sleep HANDLE_TESTS_POLLING_INTERVAL
      end
    end

    def create_project_package
      res = @tools.create_project_package(@tag)
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

    def run
      @total = @tests.count

      load_clients_system_info
      update_summary_results_log

      @last_done = []

      tests = @tests
      tests.each do |test|
        run_count = test['run_count']

        (1..run_count).each do |run_number|
          test_str = "run #{run_number}/#{run_count} #{test['name']} (#{test['id']})"
          @logger.info("Adding to queue: #{test_str}")
          queue_test(test, wait: true)
          list_tests
          handle_test_running

          break if @project.run_terminated
        end

        break if @project.run_terminated
      end
    end
  end
end
