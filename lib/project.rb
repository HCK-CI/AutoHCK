require 'json'
require 'fileutils'
require 'logger'
require './lib/github'
require './lib/dropbox'
require './lib/virthck'
require './lib/multi_delegator'
require './lib/diff_checker'

# Kit project class
class Project
  attr_reader :config, :logger, :timestamp, :platform, :device, :tag,
              :driver_path, :workspace_path, :github, :dropbox, :virthck
  PLATFORMS_JSON = 'platforms.json'.freeze
  DEVICES_JSON = 'devices.json'.freeze
  CONFIG_JSON = 'config.json'.freeze

  def initialize(options)
    init_class_variables(options)
    validate_paths
    diff_checker(options.diff)
    configure_dropbox
    github_handling(options.commit)
    init_workspace
    init_virthck
    init_multilog(options.debug)
  end

  def diff_checker(diff)
    diff_checker = DiffChecker.new(@logger, @device, @driver_path, diff)
    return if diff_checker.trigger?

    @logger.info("Driver isn't changed, not running tests")
    exit(0)
  end

  def init_multilog(debug)
    log = File.open("#{workspace_path}/#{tag}.log", 'a')
    @logger = Logger.new MultiDelegator.delegate(:write, :close).to(STDOUT, log)
    @logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    @logger.level = debug ? 'DEBUG' : 'INFO'
  end

  def init_virthck
    @virthck = VirtHCK.new(self)
  end

  def init_class_variables(options)
    @config = read_json(CONFIG_JSON)
    @timestamp = create_timestamp
    @logger = Logger.new(STDOUT)
    @logger.datetime_format = '%Y-%m-%d %H:%M:%S'
    @tag = options.tag
    @driver_path = options.path
    @device = find_device
    @platform = read_platform
  end

  def configure_dropbox
    @dropbox = Dropbox.new(self)
    @dropbox.connect
    @dropbox.create_project_folder
  end

  def github_handling(commit)
    @github = Github.new(@config, self, commit)
    return unless @github.connected?

    @github.find_pr
    return unless @github.connected?

    @github.create_status('pending', 'Tests session initiated')
  end

  def validate_paths
    normalize_paths
    validate_images
    unless File.exist?(@config['toolshck_path'])
      @logger.fatal('toolsHCK script path is not valid')
      exit(1)
    end
    unless File.exist?("#{@driver_path}/#{@device['inf']}")
      @logger.fatal('Driver path is not valid')
      exit(1)
    end
    return if File.exist?("#{@config['virthck_path']}/hck.sh")

    @logger.fatal('VirtHCK path is not valid')
    exit(1)
  end

  def normalize_paths
    @driver_path.chomp!('/')
    @config['images_path'].chomp!('/')
    @config['virthck_path'].chomp!('/')
  end

  def validate_images
    unless File.exist?("#{@config['images_path']}/#{@platform['st_image']}")
      @logger.fatal('Studio image not found')
      exit(1)
    end
    @platform['clients'].each_value do |client|
      unless File.exist?("#{@config['images_path']}/#{client['image']}")
        @logger.fatal("#{client['name']} image not found")
        exit(1)
      end
    end
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON)
    platform_name = @tag.split('-', 2).last
    @logger.info("Loading platform: #{platform_name}")
    res = platforms.find { |p| p['name'] == platform_name }
    logger.fatal("#{platform_name} does not exist") unless res
    res || exit(1)
  end

  def find_device
    devices = read_json(DEVICES_JSON)
    short_name = @tag.split('-', 2).first
    @logger.info("Loading device: #{short_name}")
    res = devices.find { |device| device['short'] == short_name }
    logger.fatal("#{short_name} does not exist") unless res
    res || exit(1)
  end

  def support?
    @device['support']
  end

  def read_json(json_file)
    JSON.parse(File.read(json_file))
  rescue Errno::ENOENT, JSON::ParserError
    @logger.fatal("Could not open #{json_file} file")
    exit(1)
  end

  def create_timestamp
    Time.now.strftime('%Y_%m_%d_%H_%M_%S')
  end

  def init_workspace
    @workspace_path = [@config['workspace_path'], @device['short'],
                       @platform['name'], @timestamp].join('/')
    begin
      FileUtils.mkdir_p(@workspace_path)
    rescue Errno::EEXIST
      @logger.warn('Workspace path already exists')
    end
  end

  def abort
    @github.handle_error if @github && @github.connected?
  end
end
