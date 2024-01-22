# frozen_string_literal: true

require 'octokit'

# AutoHCK module
module AutoHCK
  # github class
  class Github
    GITHUB_API_RETRIES = 5
    GITHUB_API_RETRY_SLEEP = 30

    def initialize(config, logger, url, tag, commit)
      @api_connected = false

      @logger = logger
      @target_url = url
      @repo = config['repository']
      @commit = commit.to_s
      @context = "HCK-CI/#{tag}"
      connect unless @commit.empty?
    end

    def connect
      login = ENV.fetch('AUTOHCK_GITHUB_LOGIN')
      password = ENV.fetch('AUTOHCK_GITHUB_TOKEN')
      @github = Octokit::Client.new(login:, password:)
      @logger.info("Connected to github with: #{@github.user.login}")
      @api_connected = true
    rescue Octokit::Unauthorized
      @logger.warn('Github authentication failed')
      nil
    end

    def connected? = @api_connected

    def find_pr = _find_pr || _find_pr('closed')

    def pr_closed?(pr_object = find_pr)
      pr_object.state == 'closed'
    end

    def log_pr(pr_object = find_pr)
      if pr_object.merged_at?
        @logger.info("PR ##{pr_object['number']}: #{pr_object['title']} - already merged")
      elsif pr_object.state == 'closed'
        @logger.info("PR ##{pr_object['number']}: #{pr_object['title']} - closed")
      else
        @logger.info("PR ##{pr_object['number']}: #{pr_object['title']}")
      end

      @logger.info(pr_object['html_url'])
    end

    def create_status(state, description)
      retries ||= 0

      options = { 'context' => @context,
                  'description' => description,
                  'target_url' => @target_url }
      begin
        @github.create_status(@repo, @commit, state, options)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError,
             Octokit::BadGateway, Octokit::InternalServerError => e
        @logger.warn("Github server connection error: #{e.message}")
        # we can continue even if can't get update PR status
        return unless (retries += 1) < GITHUB_API_RETRIES

        sleep GITHUB_API_RETRY_SLEEP
        @logger.info('Trying again execute github.create_status')
        retry
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

    def handle_cancel
      @logger.info('Updating github status regarding cancel')
      state = 'error'
      description = 'HCK-CI run was canceled'
      create_status(state, description)
    end

    def handle_error
      @logger.info('Updating github status regarding error')
      state = 'error'
      description = 'An error occurred while running HCK-CI'
      create_status(state, description)
    end

    def _find_pr(state = nil)
      retries ||= 0

      @github.pulls(@repo, state:).find { _1['head']['sha'] == @commit }
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError,
           Octokit::BadGateway, Octokit::InternalServerError => e
      @logger.warn("Github server connection error: #{e.message}")
      # we should fail if can't get updated PR information
      raise unless (retries += 1) < GITHUB_API_RETRIES

      sleep GITHUB_API_RETRY_SLEEP
      @logger.info('Trying again execute github.pulls')
      retry
    end

    private :_find_pr
  end
end
