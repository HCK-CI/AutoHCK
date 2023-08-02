# frozen_string_literal: true

require 'fileutils'
require 'mono_logger'
require './lib/engines/engine'
require './lib/setupmanagers/setupmanager'
require './lib/auxiliary/github'
require './lib/resultuploaders/result_uploader'
require './lib/auxiliary/multi_logger'
require './lib/auxiliary/diff_checker'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/id_gen'
require './lib/auxiliary/extra_software/manager'

# AutoHCK module
module AutoHCK
  # project class
  class Project
    include Helper

    attr_reader :config, :logger, :timestamp, :setup_manager, :engine, :id,
                :workspace_path, :github, :result_uploader,
                :engine_type, :options, :extra_sw_manager

    CONFIG_JSON = 'config.json'

    def initialize(scope, options)
      @scope = scope
      @options = options
      Json.update_json_override(options.common.config) unless options.common.config.nil?

      init_multilog(options.common.debug)
      init_class_variables
      init_workspace
      @id = assign_id
      scope << self
    end

    def diff_checker(drivers, diff, triggers)
      diff_checker = DiffChecker.new(@logger, drivers.map { |d| d['short'] },
                                     @options.test.driver_path, diff, triggers)
      return true if diff_checker.trigger?

      @logger.info("Any drivers aren't changed, not running tests")
      false
    end

    def check_run?
      return true if @engine.drivers.nil?

      diff_checker(@engine.drivers, @options.test.diff_file, @options.test.triggers_file)
    end

    def prepare
      @extra_sw_manager = ExtraSoftwareManager.new(self)

      @engine = Engine.new(self)
      Sentry.set_tags('autohck.tag': @engine.tag)

      return false unless check_run?

      configure_result_uploader if @engine.result_uploader_needed?
      return false unless github_handling(@options.test.commit)

      @setup_manager = SetupManager.new(self) unless @engine.platform.nil?
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

    def init_multilog(debug)
      @temp_pre_logger = StringIO.new
      @pre_logger = MonoLogger.new(@temp_pre_logger)
      @stdout_logger = MonoLogger.new($stdout)
      @logger = MultiLogger.new(@pre_logger, @stdout_logger)
      @logger.level = debug ? 'DEBUG' : 'INFO'
    end

    def append_multilog(logfile_name)
      @logfile_name = logfile_name
      @logfile_path = "#{workspace_path}/#{@logfile_name}"
      IO.copy_stream @temp_pre_logger, @logfile_path
      @pre_logger.close
      @logger.remove_logger(@pre_logger)
      @pre_logger = MonoLogger.new(@logfile_path)
      @logger.add_logger(@pre_logger)
    end

    def move_workspace_to(path)
      FileUtils.cp(@logfile_path, "#{path}/#{@logfile_name}")
      @pre_logger.close
      @logger.remove_logger(@pre_logger)
      FileUtils.rm_f(@logfile_path)
      @logfile_path = "#{path}/#{@logfile_name}"
      @pre_logger = MonoLogger.new(@logfile_path)
      @logger.add_logger(@pre_logger)
      @workspace_path = path
      @logger.info("Workspace moved to: #{@workspace_path}")
    end

    def init_class_variables
      @config = Json.read_json(CONFIG_JSON, @logger)
      @timestamp = create_timestamp
      @engine_type = @config["#{@options.mode}_engine"]
    end

    def assign_id
      @id_gen = Idgen.new(@scope, @config['id_range'], @config['time_out'])
      id = @id_gen.allocate
      while id.negative?
        @logger.info('No available ID')
        sleep 20
        id = @id_gen.allocate
      end
      @logger.info("Assigned ID: #{id}")
      id.to_s
    end

    def release_id
      @logger.info("Releasing ID: #{@id}")
      @id_gen.release(@id)
    end

    def configure_result_uploader
      @logger.info('Initializing result uploaders')
      @result_uploader = ResultUploader.new(@scope, self)
      @result_uploader.connect
      @result_uploader.create_project_folder
    end

    def github_handling_context
      "#{@options.test.gthb_context_prefix}#{@engine.tag}#{@options.test.gthb_context_suffix}"
    end

    def github_handling(commit)
      return true if commit.to_s.empty?

      url = @result_uploader.html_url || @result_uploader.url
      @github = Github.new(@config, @logger, url, github_handling_context,
                           commit)
      raise GithubCommitInvalid unless @github.connected?

      @github.find_pr
      return false if @github.pr_closed?

      raise GithubCommitInvalid unless @github.connected?

      @github.create_status('pending', 'Tests session initiated')
      true
    end

    def create_timestamp
      Time.now.strftime('%Y_%m_%d_%H_%M_%S')
    end

    def init_workspace
      @workspace_path = [@config['workspace_path'], @engine_type,
                         @config['setupmanager']].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @logger.warn('Workspace path already exists')
      end
      @logger.info("Workspace init path: #{@workspace_path}")
    end

    def handle_cancel
      @github.handle_cancel if @github&.connected?
    end

    def handle_error
      @github.handle_error if @github&.connected?
    end

    def close
      @logger.debug('Closing AutoHCK project')
      @result_uploader&.upload_file(@logfile_path, 'AutoHCK.log')
      release_id
    end
  end
end
