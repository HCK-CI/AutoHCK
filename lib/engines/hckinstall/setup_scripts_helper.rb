# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Helper module
  module Helper
    SUPPORTED_CONFIG = {
      kit_type: '',
      hlk_kit_ver: '',
      remove_gui: '',
      debug: '',
      no_reboot_after_bugcheck: ''
    }.freeze

    def copy_setup_scripts_template(workspace_hlk_setup_scripts_path, hck_setup_scripts_template_path)
      FileUtils.copy_entry(hck_setup_scripts_template_path, workspace_hlk_setup_scripts_path)
    end

    def validate_setup_scripts_config(config)
      extra_keys = (config.keys - SUPPORTED_CONFIG.keys)
      return if extra_keys.empty?

      raise(AutoHCKError, "Undefined HLK setup scripts configs: #{extra_keys.join(', ')}.")
    end

    def download_kit_installer(url, kit, workspace_hlk_setup_scripts_path)
      dw = Downloader.new(@logger)

      FileUtils.mkdir_p(workspace_hlk_setup_scripts_path.join('Kits'))
      kit_setup_path = workspace_hlk_setup_scripts_path.join('Kits', "#{kit}Setup")
      temp_path = "#{kit_setup_path}.tmp"

      dw.download(url, temp_path)

      file_type = File.read(temp_path, 2) == 'MZ' ? 'exe' : 'iso'

      kit_path = "#{kit_setup_path}.#{file_type}"
      FileUtils.mv(temp_path, kit_path)

      kit_path
    end

    def copy_extra_software(workspace_hlk_setup_scripts_path, extra_software_path, sw_names)
      workspace_extra_software_path = workspace_hlk_setup_scripts_path.join('extra-software')
      FileUtils.mkdir_p(workspace_extra_software_path)

      sw_names.each do |name|
        FileUtils.cp_r(Pathname.new(extra_software_path).join(name),
                       workspace_extra_software_path.join(name))
      end
    end

    def create_setup_scripts_config(workspace_hlk_setup_scripts_path, config)
      validate_setup_scripts_config(config)

      File.open(workspace_hlk_setup_scripts_path.join('args.ps1'), 'w') do |args_file|
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
