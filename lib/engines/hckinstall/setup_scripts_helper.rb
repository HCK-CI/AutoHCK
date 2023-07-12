# frozen_string_literal: true

require 'fileutils'

require './lib/exceptions'
require './lib/auxiliary/downloader'

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    SUPPORTED_CONFIG = {
      kit_type: '',
      hlk_kit_ver: '',
      remove_gui: '',
      debug: ''
    }.freeze

    def validate_setup_scripts_config(config)
      extra_keys = (config.keys - SUPPORTED_CONFIG.keys)
      return if extra_keys.empty?

      raise(AutoHCKError, "Undefined HLK setup scripts configs: #{extra_keys.join(', ')}.")
    end

    def download_kit_installer(url, kit, hck_setup_scripts_path)
      dw = Downloader.new(@logger)
      dw.download(url, "#{hck_setup_scripts_path}/Kits/#{kit}Setup.exe")
    end

    def copy_extra_software(hck_setup_scripts_path, extra_software_path, sw_names)
      FileUtils.rm_rf("#{hck_setup_scripts_path}/extra-software")
      FileUtils.mkdir_p("#{hck_setup_scripts_path}/extra-software")

      sw_names.each do |name|
        FileUtils.cp_r("#{extra_software_path}/#{name}",
                       "#{hck_setup_scripts_path}/extra-software/#{name}")
      end
    end

    def create_setup_scripts_config(hck_setup_scripts_path, config)
      validate_setup_scripts_config(config)

      File.open("#{hck_setup_scripts_path}/args.ps1", 'w') do |args_file|
        config.each do |k, v|
          key = k.to_s.upcase.gsub(/[^0-9a-z]/i, '')
          case v
          when true, false
            value = "$#{v}"
          when String
            value = "'#{v}'"
          when Integer
            value = v
          else
            @logger.fatal("Unexpected value #{x} for config")
            raise(AutoHCKError, "Unexpected value #{x} for config")
          end

          args_file.write("$#{key} = #{value}\n")
        end
      end
    end
  end
end
