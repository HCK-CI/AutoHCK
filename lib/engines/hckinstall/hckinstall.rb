# frozen_string_literal: true

require 'uri'

require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/auxiliary/iso_helper'
require './lib/engines/hckinstall/setup_scripts_helper'

# AutoHCK module
module AutoHCK
  # HCKInstall class
  class HCKInstall
    include Helper

    attr_reader :platform

    PLATFORMS_JSON = 'lib/engines/hcktest/platforms.json'
    CONFIG_JSON = 'lib/engines/hckinstall/hckinstall.json'
    ISO_JSON = 'lib/engines/hckinstall/iso.json'

    def initialize(project)
      @project = project
      @logger = project.logger
      @project.append_multilog("#{project.install_platform}.log")
      init_workspace
      init_config
      init_class_variables
      @logger.debug('HCKInstall: initialized')
    end

    def init_workspace
      @workspace_path = [@project.workspace_path, @project.install_platform,
                         @project.timestamp].join('/')
      begin
        FileUtils.mkdir_p(@workspace_path)
      rescue Errno::EEXIST
        @project.logger.warn('Workspace path already exists')
      end
      @project.move_workspace_to(@workspace_path.to_s)
    end

    def read_platform
      platforms = read_json(PLATFORMS_JSON, @logger)
      platform_name = @project.install_platform
      @logger.info("Loading platform: #{platform_name}")
      res = platforms.find { |p| p['name'] == platform_name }
      @logger.fatal("#{platform_name} does not exist") unless res
      res || raise(InvalidConfigFile, "#{platform_name} does not exist")
    end

    def read_iso(platform_name)
      iso = read_json(ISO_JSON, @logger)
      @logger.info("Loading ISO for platform: #{platform_name}")
      res = iso.find { |p| p['platform_name'] == platform_name }
      @logger.fatal("ISO info for #{platform_name} does not exist") unless res
      res || raise(InvalidConfigFile, "ISO info for #{platform_name} does not exist")
    end

    def init_config
      @config = read_json(CONFIG_JSON, @logger)

      @hck_setup_scripts_path = @config['hck_setup_scripts_path']

      @answer_files = @config['answer_files']
      @studio_install_timeout = @config['studio_install_timeout']
      @client_install_timeout = @config['client_install_timeout']
    end

    def client_platform
      @platform['clients'][@clients_name.first]['image'][/Win\w+x(86|64)/]
    end

    def init_class_variables
      @iso_path = @project.config['iso_path']

      @platform = read_platform
      @clients_name = @platform['clients'].keys

      @studio_iso_info = read_iso(@platform['name'])
      @client_iso_info = read_iso(client_platform)
      validate_paths

      @setup_studio_iso = "#{@workspace_path}/setup-studio.iso"
      @setup_client_iso = "#{@workspace_path}/setup-client.iso"
    end

    def validate_paths
      normalize_paths
      unless File.exist?("#{@iso_path}/#{@studio_iso_info['path']}")
        @logger.fatal('Studio ISO path is not valid')
        exit(1)
      end

      return if File.exist?("#{@iso_path}/#{@client_iso_info['path']}")

      @logger.fatal('Client ISO path is not valid')
      exit(1)
    end

    def normalize_paths
      @studio_iso_info['path'].chomp!('/')
      @client_iso_info['path'].chomp!('/')
    end

    def driver
      nil
    end

    def run_studio(snapshot = true, iso_list = [])
      st_opts = {
        studio_snapshot: snapshot,
        studio_iso_list: iso_list
      }

      st = Machine.new(@project, 'st', @project.setup_manager, 0, 'st')
      st.run(st_opts)
      st
    end

    def run_client(name, snapshot = true)
      cl_opts = {
        clients_snapshot: snapshot,
        clients_iso_list: [
          @setup_client_iso,
          @client_iso_info['path']
        ]
      }

      cl = Machine.new(@project, name, @project.setup_manager, name[/\d+/], name)
      cl.run(cl_opts)
      cl
    end

    def install_studio
      @project.setup_manager.create_studio_image

      @st = run_studio(false, [
                         @setup_studio_iso,
                         @studio_iso_info['path']
                       ])

      Timeout.timeout(@studio_install_timeout) do
        @logger.info("Waiting for #{@st.name} #{@st.id} instalation finished")
        sleep 5 while @st.alive?
      end
    end

    def install_client(name)
      @project.setup_manager.create_client_image(name)

      run_client(name, false)
    end

    def install_clients
      @project.setup_manager.create_studio_snapshot
      @st = run_studio

      @cl = @clients_name.map { |c| install_client(c) }

      @cl.each do |client|
        Timeout.timeout(@client_install_timeout) do
          @logger.info("Waiting for #{client.name} #{client.id} instalation finished")
          sleep 5 while client.alive?
        end
      end
    end

    def prepare_setup_scripts_config
      kit_string = @platform['kit']
      kit_type = kit_string[0..2]
      kit_version = 0
      kit_type == 'HCK' || kit_version = Integer(kit_string[/\d+/])

      config = {
        kit_type: kit_type,
        hlk_kit_ver: kit_version
      }
      create_setup_scripts_config(@hck_setup_scripts_path, config)
    end

    def prepare_studio_iso
      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => @studio_iso_info['windows_image_names'],
        '@PRODUCT_KEY@' => @studio_iso_info['product_key'],
        '@HOST_TYPE@' => 'studio'
      }
      @answer_files.each do |file|
        file_gsub(@hck_setup_scripts_path + "/answer-files/#{file}.in",
                  @hck_setup_scripts_path + "/#{file}", replacement_list)
      end
      create_iso(@setup_studio_iso, [@hck_setup_scripts_path])
    end

    def prepare_client_iso
      replacement_list = {
        '@WINDOWS_IMAGE_NAME@' => @client_iso_info['windows_image_names'],
        '@PRODUCT_KEY@' => @client_iso_info['product_key'],
        '@HOST_TYPE@' => 'client'
      }
      @answer_files.each do |file|
        file_gsub(@hck_setup_scripts_path + "/answer-files/#{file}.in",
                  @hck_setup_scripts_path + "/#{file}", replacement_list)
      end
      create_iso(@setup_client_iso, [@hck_setup_scripts_path])
    end

    def run
      @logger.debug('HCKInstall: run')

      prepare_setup_scripts_config

      if @project.setup_manager.check_studio_image_exist
        if @project.options.force_install
          @logger.info('HCKInstall: Studio image exist, force reinstall started')

          prepare_studio_iso
          install_studio
        else
          @logger.info('HCKInstall: Studio image exist, installation skipped')
        end
      else
        prepare_studio_iso
        install_studio
      end

      prepare_client_iso
      install_clients
    end

    def cleanup_studio
      @st&.abort
      @project&.setup_manager&.delete_studio_snapshot
    end

    def cleanup_clients
      @cl&.map(&:abort)
      @clients_name.each do |client|
        @project&.setup_manager&.delete_client_snapshot(client)
      end
    end

    def close
      @logger.debug('HCKInstall: close')

      cleanup_studio
      cleanup_clients
    end
  end
end
