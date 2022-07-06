# frozen_string_literal: true

require 'date'
require 'fileutils'
require './lib/engines/hcktest/playlist'
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

    def initialize(client, support, project, target, tools)
      @client = client
      @project = project
      @tag = project.engine.tag
      @target = target
      @tools = tools
      @support = support
      @logger = project.logger
      @playlist = Playlist.new(client, project, target, tools, @client.kit)
      @tests_extra = {}
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

    def check_test_queued_time
      # We can't compare test objects directly because the list_tests
      # function updates the test object but the current_test function
      # returns the pure object.
      return if @last_queued_id == current_test&.dig('id')

      diff = time_diff(@tests_extra[@last_queued_id]['queued_at'], DateTime.now)

      return if diff < time_to_seconds(QUEUE_TEST_TIMEOUT)

      @logger.warn("Test was queued #{seconds_to_time(diff)} ago! HCK hangs on?")
    end

    def wait_queued_test(id)
      loop do
        sleep 5
        test = @tools.get_test_info(id, @target['key'], @client.name, @tag)

        check_test_queued_time

        break if test['executionstate'] != 'NotRunning'
        break if test['status'] == 'InQueue'
        break if test_finished?(test)
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
        'currentcount' => done_tests.count + 1, 'total' => @total }
    end

    def test_finished?(test)
      %w[Passed Failed].include? test['status']
    end

    def done_tests
      @tests.select { |test| test_finished?(test) }
    end

    def info_page(test)
      url = 'https://docs.microsoft.com/en-us/windows-hardware/test/hlk/testref/'
      "Test information page: #{url}#{test['id']}"
    end

    def on_test_start(test)
      @logger.info('>>> Currently running: '\
                  "#{test['name']} [#{test['estimatedruntime']}]")

      @tests_extra[test['id']]['started_at'] = DateTime.now
    end

    def print_tests_stats
      stats = tests_stats
      @logger.info("<<< Passed: #{stats['passed']} | Failed: #{stats['failed']} | "\
                   "InQueue: #{stats['inqueue']}")
    end

    def print_test_results(test)
      results = @tests.find { |t| t['id'] == test['id'] }
      @logger.info("#{results['status']}: #{test['name']}")
      @logger.info(info_page(test))
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

    def summary_blacklisted_log
      @playlist.blacklisted.reduce('') do |sum, test|
        sum + "Skipped: #{test['name']} [#{test['estimatedruntime']}]\n"
      end
    end

    def summary_results_log
      @tests.reduce('') do |sum, test|
        extra_info = @tests_extra.dig(test['id'], 'dump') ? '(with Minidump)' : ''
        sum + "#{test['status']}: #{test['name']} [#{test['estimatedruntime']}] #{extra_info}\n"
      end
    end

    def update_summary_results_log
      logs = summary_blacklisted_log
      logs += summary_results_log

      @logger.info('Tests results logs updated via the result uploader')
      @project.result_uploader.update_file_content(logs, 'logs.txt')
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

    def collect_memory_dump(machine, l_tmp_path)
      exist = @tools.exists_on_machine?(machine, '${env:SystemRoot}/Minidump')
      @logger.debug("Checking Minidump exist on #{machine}: #{exist}")
      return false unless exist

      @logger.info("Downloading memory dump (Minidump) from #{machine}")
      @tools.download_from_machine(machine, '${env:SystemRoot}/Minidump', l_tmp_path)
      @tools.delete_on_machine(machine, '${env:SystemRoot}/Minidump')

      true
    end

    def collect_memory_dumps(test)
      id = test['id']

      l_zip_path = "#{@project.workspace_path}/memory_dump_#{id}.zip"
      l_tmp_path = "#{@project.workspace_path}/tmp_#{id}"

      collected_client = collect_memory_dump(@client.name, "#{l_tmp_path}/#{@client.name}")
      collected_support = collect_memory_dump(@support.name, "#{l_tmp_path}/#{@support.name}") unless @support.nil?

      if collected_client || collected_support
        create_zip_from_directory(l_zip_path, l_tmp_path)
        @tests_extra[id]['dump'] = l_zip_path
      end

      FileUtils.rm_rf(l_tmp_path)
    end

    def handle_finished_tests(tests)
      tests.each do |test|
        @project.github.update(tests_stats) if @project.github&.connected?

        collect_memory_dumps(test)

        print_test_results(test)
        archive_test_results(test)
      end
      print_tests_stats
      @last_queued_id = nil
    end

    def reset_clients_to_ready_state
      @client.reset_to_ready_state
      @support&.reset_to_ready_state
    end

    def keep_clients_alive
      @client.keep_alive
      @support&.keep_alive
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

    def handle_test_running(running = nil)
      until all_tests_finished?
        keep_clients_alive
        reset_clients_to_ready_state
        check_new_finished_tests
        check_test_queued_time
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

    def run
      @last_done = []
      @total = @tests.count
      tests = @tests
      tests.each do |test|
        @logger.info("Adding to queue: #{test['name']} [#{test['estimatedruntime']}]")
        queue_test(test, wait: true)
        list_tests
        handle_test_running
      end
    end
  end
end
