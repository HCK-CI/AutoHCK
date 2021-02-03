# frozen_string_literal: true

require 'fileutils'
require 'mono_logger'
require 'tempfile'
require './lib/auxiliary/github'
require './lib/resultuploaders/result_uploader'
require './lib/auxiliary/multi_logger'
require './lib/auxiliary/diff_checker'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/id_gen'

# project class
class Project
  attr_reader :config, :logger, :timestamp, :setupmanager, :engine, :tag, :id,
              :driver, :driver_path, :workspace_path, :github, :result_uploader
  DRIVERS_JSON = './drivers.json'
  CONFIG_JSON = 'config.json'

  def initialize(options)
    init_multilog(options.debug)
    init_class_variables(options)
    validate_paths
    diff_checker(options.diff)
    configure_result_uploader
    github_handling(options.commit)
    init_workspace
    append_multilog
    @id = assign_id
  end

  def diff_checker(diff)
    diff_checker = DiffChecker.new(@logger, @driver, @driver_path, diff)
    return if diff_checker.trigger?

    @logger.info("Driver isn't changed, not running tests")
    exit(0)
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
    @temp_pre_logger_file = Tempfile.new('')
    @temp_pre_logger_file.sync = true
    @pre_logger = MonoLogger.new(@temp_pre_logger_file)
    @stdout_logger = MonoLogger.new(STDOUT)
    @logger = MultiLogger.new(@pre_logger, @stdout_logger)
    @logger.level = debug ? 'DEBUG' : 'INFO'
  end

  def append_multilog
    @logfile_path = "#{workspace_path}/#{tag}.log"
    FileUtils.cp(@temp_pre_logger_file.path, @logfile_path)
    @pre_logger.close
    @temp_pre_logger_file.unlink
    @logger.remove_logger(@pre_logger)
    @pre_logger = MonoLogger.new(@logfile_path)
    @logger.add_logger(@pre_logger)
  end

  def move_workspace_to(path)
    FileUtils.cp(@logfile_path, "#{path}/#{tag}.log")
    @logfile_path = "#{path}/#{tag}.log"
    @pre_logger.close
    @logger.remove_logger(@pre_logger)
    @pre_logger = MonoLogger.new(@logfile_path)
    @logger.add_logger(@pre_logger)
    @workspace_path = path
  end

  def init_class_variables(options)
    @config = read_json(CONFIG_JSON, @logger)
    @timestamp = create_timestamp
    @tag = options.tag
    @driver_path = options.path
    @driver = find_driver
    @engine = @config['engine']
    @setupmanager = @config['setupmanager']
  end

  def assign_id
    @id_gen = Idgen.new(@config['id_range'], @config['time_out'])
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
    @result_uploader = ResultUploader.new(self)
    @result_uploader.connect
    @result_uploader.create_project_folder
  end

  def github_handling(commit)
    return if commit.to_s.empty?

    @github = Github.new(@config, @logger, @result_uploader.url, @tag, commit)
    raise GithubCommitInvalid unless @github.connected?

    @github.find_pr
    raise GithubCommitInvalid unless @github.connected?

    @github.create_status('pending', 'Tests session initiated')
  end

  def validate_paths
    normalize_paths
    return if File.exist?("#{@driver_path}/#{@driver['inf']}")

    @logger.fatal('Driver path is not valid')
    exit(1)
  end

  def normalize_paths
    @driver_path.chomp!('/')
  end

  def find_driver
    drivers = read_json(DRIVERS_JSON, @logger)
    short_name = @tag.split('-', 2).first
    @logger.info("Loading driver: #{short_name}")
    res = drivers.find { |driver| driver['short'] == short_name }
    logger.fatal("#{short_name} does not exist") unless res
    res || exit(1)
  end

  def create_timestamp
    Time.now.strftime('%Y_%m_%d_%H_%M_%S')
  end

  def init_workspace
    @workspace_path = [@config['workspace_path'], @driver['short'],
                       @config['engine'], @config['setupmanager']].join('/')
    begin
      FileUtils.mkdir_p(@workspace_path)
    rescue Errno::EEXIST
      @logger.warn('Workspace path already exists')
    end
  end

  def handle_cancel
    @github.handle_cancel if @github&.connected?
  end

  def handle_error
    @github.handle_error if @github&.connected?
  end

  def abort
    @result_uploader.upload_file(@logfile_path, 'AutoHCK.log')
    @logger.remove_logger(@stdout_logger)
  end

  def close
    @client1&.abort
    @client2&.abort
    @studio&.abort
    @setup_manager&.close
    release_id
  end
end
