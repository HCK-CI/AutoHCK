# frozen_string_literal: true

require 'octokit'

# AutoHCK module
module AutoHCK
  # github class
  class Github
    def initialize(config, logger, url, tag, commit)
      @api_connected = false
      @pr_closed = nil

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

    def connected?
      @api_connected
    end

    def pr_closed?
      @pr_closed
    end

    def check_closed_pr
      pr = @github.pulls(@repo, state: 'closed').find { |x| x['head']['sha'] == @commit }

      return false if pr.nil?

      @pr_closed = true
      if pr.merged_at?
        @logger.warn("PR ##{pr['number']}: #{pr['title']} - already merged. Skipping CI.")
      else
        @logger.warn("PR ##{pr['number']}: #{pr['title']} - closed. Skipping CI.")
      end

      true
    end

    def find_pr
      pr = @github.pulls(@repo).find { |x| x['head']['sha'] == @commit }
      if pr.nil?
        unless check_closed_pr
          @logger.warn('Pull request commit hash not valid, disconnecting github.')
          @api_connected = false
        end

        return nil
      end

      @logger.info("PR ##{pr['number']}: #{pr['title']}")
      @logger.info(pr['html_url'])

      pr
    end

    def create_status(state, description)
      options = { 'context' => @context,
                  'description' => description,
                  'target_url' => @target_url }
      begin
        @github.create_status(@repo, @commit, state, options)
      rescue Faraday::ConnectionFailed, Octokit::BadGateway
        @logger.warn('Github server connection error')
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
  end
end
