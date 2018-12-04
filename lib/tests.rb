require './lib/playlist'
# Tests class
class Tests
  HANDLE_TESTS_POLLING_INTERVAL = 10
  APPLYING_FILTERS_INTERVAL = 50
  def initialize(client, support, project, target, tools)
    @client = client
    @project = project
    @tag = project.tag
    @target = target
    @tools = tools
    @support = support
    @logger = project.logger
    @playlist = Playlist.new(client, project, target, tools)
  end

  def list_tests(log = false)
    @tests = @playlist.list_tests(log)
  end

  def support_needed?(test)
    (test['scheduleoptions'] & %w[6 RequiresMultipleMachines]) != []
  end

  def test_support(test)
    @support.machine['name'] if support_needed?(test)
  end

  def queue_test(test)
    @tools.queue_test(test['id'], @target['key'], @client.machine['name'],
                      @tag, test_support(test))
  end

  def current_test
    @tests.find { |test| test['executionstate'] == 'Running' }
  end

  def status_count(status)
    @tests.count { |test| test['status'] == status }
  end

  def tests_stats
    { 'current' => current_test, 'passed' => status_count('Passed'),
      'failed' => status_count('Failed'), 'inqueue' => status_count('InQueue'),
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
    @logger.info("<<< Passed: #{stats['passed']} | Failed: #{stats['failed']} |\
InQueue: #{stats['inqueue']}")
  end

  def print_test_results(test)
    results = @tests.find { |t| t['id'] == test['id'] }
    @logger.info(results['status'] + ': ' + test['name'])
    @logger.info(info_page(test))
  end

  def archive_test_results(test)
    res = @tools.zip_test_result_logs(test['id'], @target['key'],
                                      @client.machine['name'], @tag)
    @logger.info('Test archive successfully created')
    new_filename = res['status'] + ': ' + res['testname']
    update_remote(res['hostlogszippath'], new_filename)
    @logger.info('Test archive uploaded via the result uploader')
  end

  def update_remote(test_logs_path, test_name)
    r_name = test_name + File.extname(test_logs_path)
    @project.result_uploader.upload_file(test_logs_path, r_name)
    logs = @tests.reduce('') do |sum, test|
      sum + "#{test['status']}: #{test['name']}\n"
    end
    @logger.info('Tests results logs updated via the result uploader')
    @project.result_uploader.update_file_content(logs, 'logs.txt')
  end

  def all_tests_finished?
    status_count('InQueue').zero? && current_test.nil?
  end

  def handle_finished_tests(tests)
    tests.each do |test|
      @project.github.update(tests_stats) if @project.github.connected?
      print_test_results(test)
      archive_test_results(test)
    end
    print_tests_stats
  end

  def keep_clients_alive
    @client.keep_alive
    @support.keep_alive
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
    @last_done = []
    until all_tests_finished?
      keep_clients_alive
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
    @total = @tests.count
    @logger.info('Adding tests to queue')
    @tests.each { |test| queue_test(test) }
    list_tests(true)
    handle_test_running
  end
end
