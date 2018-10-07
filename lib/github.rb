require 'octokit'

# github class
class Github
  def initialize(config, project, commit)
    @up = false
    @logger = project.logger
    @target_url = project.dropbox.url
    @repo = config['repository']
    @commit = commit.to_s
    @context = "HCK-CI/#{project.tag}"
    @credentials = config['github_credentials']
    connect unless @commit.empty?
  end

  def connect
    login = @credentials['login']
    password = @credentials['password']
    @github = Octokit::Client.new(login: login, password: password)
    @logger.info("Connected to github with: #{@github.user.login}")
    @up = true
  rescue Octokit::Unauthorized
    @logger.error('Github authentication failed')
    nil
  end

  def up?
    @up
  end

  def find_pr
    pr = @github.pulls(@repo).find { |x| x['head']['sha'] == @commit }
    if pr.nil?
      @logger.error('Pull request commit hash not valid')
      @up = false
      return nil
    end
    unless pr.nil?
      @logger.info("PR ##{pr['number']}: #{pr['title']}")
      @logger.info(pr['html_url'])
    end
    pr
  end

  def create_status(state, description)
    options = { 'context' => @context,
                'description' => description,
                'target_url' => @target_url }
    begin
      @github.create_status(@repo, @commit, state, options)
    rescue Faraday::ConnectionFailed
      @logger.error('Github server connection error')
    end
    @logger.info('Github status updated')
  end

  def update(tests_stats)
    if tests_stats['current'].nil? && tests_stats['inqueue'].zero?
      if tests_stats['failed'].zero?
        handle_success
      else
        handle_failure(tests_stats['failed'], tests_stats['passed'])
      end
    else
      handle_pending(tests_stats['currentcount'], tests_stats['total'],
                     tests_stats['failed'])
    end
  end

  def handle_success
    state = 'success'
    description = 'All tests passed'
    create_status(state, description)
  end

  def handle_failure(failed, passed)
    state = 'failure'
    description = "#{failed} tests failed out  of #{failed + passed} tests"
    create_status(state, description)
  end

  def handle_pending(current, total, failed)
    state = 'pending'
    description = "Running tests (#{current}/#{total}): #{failed} tests failed"
    create_status(state, description)
  end
end
