# frozen_string_literal: true

require './lib/engines/hcktest/playlist'

# AutoHCK module
module AutoHCK
  # Tests class
  class Tests
    HANDLE_TESTS_POLLING_INTERVAL = 10
    APPLYING_FILTERS_INTERVAL = 50
    VERIFY_TARGET_RETRIES = 5
    VERIFY_TARGET_SLEEP = 5
    def initialize(client, support, project, target, tools)
      @client = client
      @project = project
      @tag = project.tag
      @target = target
      @tools = tools
      @support = support
      @logger = project.logger
      @playlist = Playlist.new(client, project, target, tools, @client.kit)
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

    def queue_test(test, wait: false)
      @tools.queue_test(test['id'], @target['key'], @client.name, @tag,
                        test_support(test))
      return unless wait

      loop do
        sleep 5
        test = @tools.get_test_info(test['id'], @target['key'], @client.name, @tag)
        break if test['executionstate'] == 'InQueue'
      end
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

    def done_tests
      @tests.select { |test| %w[Passed Failed].include? test['status'] }
    end

    def info_page(test)
      url = 'https://docs.microsoft.com/en-us/windows-hardware/test/hlk/testref/'
      "Test information page: #{url}#{test['id']}"
    end

    def print_test_info_when_start(test)
      @logger.info('>>> Currently running: '\
                  "#{test['name']} [#{test['estimatedruntime']}]")
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
      update_remote(res['hostlogszippath'], res['status'], res['testname'])
      @logger.info('Test archive uploaded via the result uploader')
    rescue Tools::ZipTestResultLogsError
      @logger.info('Skipping archiving test result logs')
    end

    def update_remote(test_logs_path, status, testname)
      delete_old_remote(testname)
      new_filename = "#{status}: #{testname}"
      r_name = new_filename + File.extname(test_logs_path)
      @project.result_uploader.upload_file(test_logs_path, r_name)
      logs = @tests.reduce('') do |sum, test|
        sum + "#{test['status']}: #{test['name']}\n"
      end
      @logger.info('Tests results logs updated via the result uploader')
      @project.result_uploader.update_file_content(logs, 'logs.txt')
    end

    def delete_old_remote(test_name)
      r_name = "Failed: #{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
      r_name = "Passed: #{test_name}.zip"
      @project.result_uploader.delete_file(r_name)
    end

    def all_tests_finished?
      status_count('InQueue').zero? && current_test.nil?
    end

    def handle_finished_tests(tests)
      tests.each do |test|
        @project.github.update(tests_stats) if @project.github&.connected?
        print_test_results(test)
        archive_test_results(test)
      end
      print_tests_stats
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
        if current_test != running
          running = current_test
          print_test_info_when_start(running) if running
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
