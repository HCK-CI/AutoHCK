# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # project class
  class Project
    include Helper
    JUNIT_RESULT = 'junit.xml'

    attr_reader :config, :logger, :timestamp, :setup_manager, :engine, :id,
                :workspace_path, :github, :result_uploader, :engine_tag,
                :engine_platform, :engine_type, :options, :extra_sw_manager,
                :run_terminated, :engine_name, :string_log

    def initialize(scope, options)
      @scope = scope
      @options = options
      init_timestamp
      Json.update_json_override(options.common.config) unless options.common.config.nil?
      init_multilog(options.common.verbose)
      init_class_variables
      init_workspace
      @id = options.common.id
      # ResultUploader must be initialized before adding project to scope
      # Project uses ResultUploader on close, so ResultUploader must exist
      # when project is closed
      @result_uploader = ResultUploader.new(@scope, self)

      scope << self
    end

    def prepare
      @extra_sw_manager = ExtraSoftwareManager.new(self)

      @engine = @engine_type.new(self)
      Sentry.set_tags('autohck.tag': @engine_tag)

      configure_result_uploader if @engine.result_uploader_needed?
      return false unless github_handling(@options.test.commit)

      @setup_manager = @setup_manager_type&.new(self)

      true
    end

    def run
      @engine.run
    end

    def prep_stream_for_log(stream)
      stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
    end

    def log_exception(exception, level)
      eclass = exception.class
      emessage = exception.message
      estack = prep_stream_for_log(exception.backtrace.join("\n"))
      @logger.public_send(level, "(#{eclass}) #{emessage}#{estack}")
    end

    def init_multilog(verbose)
      @string_log = StringIO.new
      string_logger = MonoLogger.new(@string_log)
      stderr_logger = MonoLogger.new($stderr)
      @logger = MultiLogger.new(string_logger, stderr_logger)
      @logger.level = verbose ? 'DEBUG' : 'INFO'
    end

    def append_multilog(logfile_name)
      @logfile_name = logfile_name
      @logfile_path = "#{workspace_path}/#{@logfile_name}"
      IO.copy_stream @string_log, @logfile_path
      @logger.add_logger(MonoLogger.new(@logfile_path))
    end

    def init_timestamp
      unless @options.common.workspace_path.nil?
        @timestamp = @options.common.workspace_path.split('/').last
        return
      end

      @timestamp = current_timestamp
    end

    def init_class_variables
      @config = Config.read
      @engine_name = @config["#{@options.mode}_engine"]
      @engine_type = Engine.select(@engine_name)
      @engine_tag = @engine_type.tag(@options)
      @engine_platform = @engine_type.platform(@logger, @options)
      @setup_manager_type = @engine_platform.nil? ? nil : SetupManager.select(@engine_platform['setupmanager'])
      @run_terminated = false
      @junit = JUnit.new(self)
    end

    def configure_result_uploader
      @logger.info('Initializing result uploaders')
      @result_uploader.connect
      @result_uploader.create_project_folder
    end

    def github_handling_context
      "HCK-CI/#{@options.test.gthb_context_prefix}#{@engine_tag}#{@options.test.gthb_context_suffix}"
    end

    def initialize_github(commit)
      url = @result_uploader.html_url || @result_uploader.url

      @github = Github.new(@config['repository'], @logger, url,
                           github_handling_context, commit)
      @github.connect
      raise GithubInitializationError unless @github.connected?
    end

    def github_handling(commit)
      return true if commit.to_s.empty?

      initialize_github(commit)

      pr = @github.find_pr

      if pr.nil?
        @logger.warn('Pull request commit hash not valid, terminating CI')
        # Do not raise an exception. If the commit is not valid
        # it can be because PR was force-pushed. Just exit from
        # CI with the corresponding message.
        return false
      end

      @github.log_pr(pr)

      return false if @github.pr_closed?(pr)

      return false unless @github.pr_check_run(pr)

      @github.create_status('pending', 'Tests session initiated')
      true
    end

    def check_run_termination
      return if @github.nil?

      begin
        pr = @github.find_pr
      rescue GithubPullRequestLoadError => e
        @logger.warn("Error while checking PR status: #{e}")
        @logger.warn('Continuing CI run, PR status will be checked later')
        return
      end
      # PR is nil when it was force-pushed
      # PR is closed when it was closed or merged
      @run_terminated = pr.nil? || @github.pr_closed?(pr)

      return unless @run_terminated

      @logger.warn('Pull request changed, terminating CI')
      @github.handle_cancel
    end

    def init_workspace
      unless @options.common.workspace_path.nil?
        @workspace_path = @options.common.workspace_path
        return
      end

      @workspace_path = File.join(@config['workspace_path'],
                                  @engine_name,
                                  @engine_tag,
                                  @timestamp)
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @logger.warn('Workspace path already exists')
      end
      @logger.info("Workspace path: #{@workspace_path}")

      begin
        File.delete("#{@config['workspace_path']}/latest")
      rescue Errno::ENOENT
        # firts run, no symlink to delete
      end

      File.symlink(@workspace_path, "#{@config['workspace_path']}/latest")
      @setup_manager_type&.enter @workspace_path
    end

    def handle_cancel
      @github.handle_cancel if @github&.connected?
    end

    def handle_error
      @github.handle_error if @github&.connected?
    end

    def generate_junit
      results_file = "#{@workspace_path}/#{JUNIT_RESULT}"

      @junit.generate(results_file)

      @result_uploader.delete_file(JUNIT_RESULT)
      @result_uploader.upload_file(results_file, JUNIT_RESULT)
    end

    def close
      @logger.debug('Closing AutoHCK project')
      generate_junit

      @result_uploader&.upload_file(@logfile_path, 'AutoHCK.log')
    end
  end
end
