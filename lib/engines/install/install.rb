# frozen_string_literal: true

require 'uri'

require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/auxiliary/xml_helper'

# Install class
class Install
  PLATFORMS_JSON = 'lib/engines/platforms.json'
  CONFIG_JSON = 'config.json'
  ISO_JSON = 'lib/engines/iso.json'

  # This is a temporary workaround for clients names
  CLIENTS = {
    CL1: 'c1',
    CL2: 'c2'
  }.freeze
  SM_RETRIES = 5

  def initialize(project)
    @project = project
    @logger = project.logger
    init_class_variables
    @logger.info("Install: initialized")
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON, @logger)
    platform_name = @project.install
    @logger.info("Loading platform: #{platform_name}")
    res = platforms.find { |p| p['name'] == platform_name }
    @logger.fatal("#{platform_name} does not exist") unless res
    res || raise(InvalidConfigFile, "#{platform_name} does not exist")
  end

  def read_iso
    iso = read_json(ISO_JSON, @logger)
    platform_name = @project.install
    @logger.info("Loading ISO for platform: #{platform_name}")
    res = iso.find { |p| p['platform_name'] == platform_name }
    @logger.fatal("ISO info for #{platform_name} does not exist") unless res
    res || raise(InvalidConfigFile, "ISO info for #{platform_name} does not exist")
  end

  def init_class_variables()
    @config = read_json(CONFIG_JSON, @logger)

    @iso_path = @config['iso_path']
    @hck_setup_scripts_path = @config['hck_setup_scripts_path']

    @platform = read_platform
    @iso = read_iso

    validate_paths
  end

  def validate_paths
    normalize_paths
    return if File.exist?("#{@iso_path}/#{@iso['path']}")

    @logger.fatal('ISO path is not valid')
    exit(1)
  end

  def normalize_paths
    @iso['path'].chomp!('/')
  end

  def run
    @logger.info("Install: run")
    dest_iso = '/tmp/20210201-171087-1on6an4.iso'
    run_cmd(['mkisofs', '-iso-level','4', '-l', '-R', '-udf', '-D', '-o',
      dest_iso, @hck_setup_scripts_path])

    f = read_xml(@hck_setup_scripts_path + '/answer-files/autounattend.xml.in', @logger)
    update_xml(f, [{"asd"=>"sss"}, {"@WINDOWS_IMAGE_NAME@"=>"THIS IS NAME"}], @logger)
    print f.to_xml
  end

  def close
    @logger.info("Install: close")
  end
end
