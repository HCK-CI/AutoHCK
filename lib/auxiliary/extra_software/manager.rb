# frozen_string_literal: true

require 'pathname'

require './lib/auxiliary/downloader'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/string_helper'
require './lib/auxiliary/extra_software/exceptions'
require './lib/engines/hckinstall/setup_scripts_helper'

# AutoHCK module
module AutoHCK
  # ExtraSoftwareManager class
  class ExtraSoftwareManager
    include Helper

    ALLOWED_INSTALL_TIME_VALUE = %w[before after].freeze

    def initialize(project)
      @logger = project.logger
      @ext_path = project.config['extra_software']

      @sw_names = []
      @sw_configs = {}
    end

    def download_software(name, config)
      path = Pathname.new(@ext_path).join(name).join(config['file_name'])

      if File.exist?(path)
        @logger.info("#{config['file_name']} already exist, download skipped")
        return
      end

      dw = Downloader.new(@logger)
      dw.download(config['download_url'],
                  Pathname.new(@ext_path).join(name).join(config['file_name']))
    end

    def read_config(name, kit)
      paths = [
        Pathname.new(@ext_path).join(name).join("#{kit.downcase}-config.json"),
        Pathname.new(@ext_path).join(name).join('config.json')
      ]
      paths.each do |path|
        return read_json(path, @logger) if File.exist?(path)
      end

      raise(ExtraSoftwareMissingConfig,
            "Failed to find any config files: #{paths.join}")
    end

    def validate_software(name, config)
      unless ALLOWED_INSTALL_TIME_VALUE.include?(config['install_time']['kit']) &&
             ALLOWED_INSTALL_TIME_VALUE.include?(config['install_time']['driver'])
        raise(ExtraSoftwareBrokenConfig,
              "#{name}: unknown install time value")
      end

      if config['install_time']['kit'] == 'before' &&
         config['install_time']['driver'] == 'after'
        raise(ExtraSoftwareBrokenConfig,
              "#{name}: kit install time is before, but the driver - after")
      end
    end

    def check_install_needed(name, config, engine_mode)
      if engine_mode == 'install'
        if config['install_time']['driver'] == 'after'
          @logger.warn("SW #{name}: Skip installation in install mode, because any driver will not be installed")
          return false
        end
      elsif config['install_time']['kit'] == 'before'
        @logger.warn("SW #{name}: Skip installation in test mode, because HLK kit already installed")
        return false
      end

      true
    end

    def prepare_software_packages(sw_names, kit, engine_mode)
      sw_names.each do |name|
        next if @sw_names.include?(name)

        config = read_config(name, kit)
        validate_software(name, config)
        next unless check_install_needed(name, config, engine_mode)

        @sw_names += [name]
        @sw_configs[name] = config
        download_software(name, config)
      end
    end

    def copy_to_setup_scripts(setup_scripts_path)
      copy_extra_software(setup_scripts_path, @ext_path, @sw_names)
    end

    def install_software_on_computer(sw_name, sw_config, tools, machine_name)
      @logger.info("Installing #{sw_name} on #{machine_name}")
      path = tools.upload_to_machine(machine_name, Pathname.new(@ext_path).join(sw_name))
      path = path.tr('/', '\\')

      replacement_list = {
        '@sw_path@' => path,
        '@file_name@' => sw_config['file_name'],
        '@temp@' => '${env:TEMP}'
      }

      cmd = "#{sw_config['install_cmd']} #{sw_config['install_args']}"
      full_cmd = replace_string(cmd, replacement_list)

      @logger.debug("cmd #{machine_name}:\n - path = #{path}\n - cmd = #{cmd}\n - full_cmd = #{full_cmd}\n")
      tools.run_on_machine(machine_name, "Installing #{sw_name}", full_cmd)
    end

    def install_software_before_driver(tools, machine_name)
      @sw_names.each do |name|
        sw_config = @sw_configs[name]
        if sw_config['install_time']['driver'] == 'before'
          install_software_on_computer(name, sw_config, tools,
                                       machine_name)
        end
      end
    end

    def install_software_after_driver(tools, machine_name)
      @sw_names.each do |name|
        sw_config = @sw_configs[name]
        if sw_config['install_time']['driver'] == 'after'
          install_software_on_computer(name, sw_config, tools,
                                       machine_name)
        end
      end
    end
  end
end
