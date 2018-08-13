require './lib/playlist'
# Tests class
class Tests
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

  def test_support(test)
    multiple = (test['scheduleoptions'] & %w[6 RequiresMultipleMachines]) != []
    @support.machine['name'] if multiple
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

  def print_test_info(running)
    @logger.info("Test (#{tests_stats['currentcount']}/#{@total}):"\
                 " #{running['name']} [#{running['estimatedruntime']}]")
    @logger.info(info_page(running))
  end

  def print_tests_stats
    stats = tests_stats
    @logger.info("Passed: #{stats['passed']} | Failed: #{stats['failed']} |\
InQueue: #{stats['inqueue']}")
  end

  def print_test_results(test)
    results = @tests.find { |t| t['id'] == test['id'] }
    @logger.info("The test ended ; Test results: #{results['status']}")
  end

  def archive_test_results(test)
    res = @tools.get_test_results(test['id'], @target['key'],
                                  @client.machine['name'], @tag)
    @logger.info('Test archive successfully created')
    update_remote(res['hostlogzippath'], res['result'] + ': ' + test['name'])
  end

  def update_remote(test_logs_path, test_name)
    @project.dropbox.upload(test_logs_path, test_name)
    logs = @tests.reduce('') do |sum, test|
      sum + "#{test['name']}: #{test['status']}\n"
    end
    @project.dropbox.upload_text(logs, 'logs.txt')
  end

  def all_tests_finished?
    tests_stats['inqueue'].zero? && tests_stats['current'].nil?
  end

  def handle_finished_test(test)
    @project.github.update(tests_stats) if @project.github.up?
    print_test_results(test)
    archive_test_results(test)
    print_tests_stats
  end

  def keep_clients_alive
    @client.keep_alive
    @support.keep_alive if @support
  end

  def handle_test_running(running = nil)
    until all_tests_finished?
      keep_clients_alive
      list_tests
      next if tests_stats['current'] == running
      handle_finished_test(running) if running
      running = tests_stats['current']
      print_test_info_when_start(running) if running
    end
  end

  def create_project_package
    res = @tools.create_project_package(@tag)
    @logger.info('Results package successfully created')
    @project.dropbox.upload(res['hostprojectpackagepath'], @tag)
  end

  def run
    @total = @tests.count
    @logger.info('Adding tests to queue')
    @tests.each { |test| queue_test(test) }
    list_tests(true)
    handle_test_running
    @logger.info('All tests finished running.')
    create_project_package
  end
end
