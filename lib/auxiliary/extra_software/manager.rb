# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # ExtraSoftwareManager class
  class ExtraSoftwareManager
    include Helper

    ALLOWED_INSTALL_TIME_VALUE = %w[before after].freeze

    def initialize(project)
      @project = project
      @logger = project.logger
      @ext_path = project.config['extra_software']

      @sw_names = []
      @sw_configs = {}
    end

    def download_software(name, config)
      file_name = config['file_name']
      path = Pathname.new(@ext_path).join(name).join(file_name)

      if File.exist?(path)
        @logger.info("#{file_name} already exists, download skipped")
        return
      end

      if config['download_url'].nil? || config['download_url'].empty?
        msg = "#{name}: download URL and expected file '#{path}' are missing, cannot download/use software package"
        @logger.error(msg)
        raise(ExtraSoftwareBrokenConfig, msg)
      end

      dw = Downloader.new(@logger)
      dw.download(config['download_url'], path)
    end

    def read_config(name, kit, arch)
      paths = config_path_candidates(name, kit, arch)
      paths.each do |path|
        next unless File.exist?(path)

        @logger.info("Loading extra software by name '#{name}' for kit '#{kit}' " \
                     "arch '#{arch}' from #{path}")
        return Json.read_json(path.to_s, @logger)
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

    def prepare_software_packages(sw_names, kit, engine_mode, arches: nil)
      arches ||= platform_arches(include_studio: engine_mode == 'install')

      sw_names.each do |name|
        arches.each do |arch|
          config_key = sw_config_key(name, arch)
          next if @sw_configs.key?(config_key)

          config = read_config(name, kit, arch)
          validate_software(name, config)
          next unless check_install_needed(name, config, engine_mode)

          @sw_names |= [name]
          @sw_configs[config_key] = config
          download_software(name, config)
        end
      end
    end

    def copy_to_setup_scripts(setup_scripts_path)
      copy_extra_software(setup_scripts_path, @ext_path, @sw_names)
    end

    def install_software_on_computer(sw_name, sw_config, tools, machine_name)
      @logger.info("Installing #{sw_name} on #{machine_name}")
      path = tools.upload_to_machine(machine_name, Pathname.new(@ext_path).join(sw_name))
      path = path.tr('/', '\\')

      replacement_map = ReplacementMap.new(
        '@sw_path@' => path,
        '@file_name@' => sw_config['file_name'],
        '@temp@' => '${env:TEMP}'
      )

      cmd = "#{sw_config['install_cmd']} #{sw_config['install_args']}"
      full_cmd = replacement_map.replace(cmd)

      @logger.debug("cmd #{machine_name}:\n - path = #{path}\n - cmd = #{cmd}\n - full_cmd = #{full_cmd}\n")
      tools.run_on_machine(machine_name, "Installing #{sw_name}", full_cmd)
    end

    def install_software_before_driver(tools, machine_name)
      arch = machine_arch(machine_name)
      @sw_names.each do |name|
        sw_config = sw_config_for(name, arch)
        next unless sw_config
        next unless sw_config['install_time']['driver'] == 'before'

        install_software_on_computer(name, sw_config, tools, machine_name)
      end
    end

    def install_software_after_driver(tools, machine_name)
      arch = machine_arch(machine_name)
      @sw_names.each do |name|
        sw_config = sw_config_for(name, arch)
        next unless sw_config
        next unless sw_config['install_time']['driver'] == 'after'

        install_software_on_computer(name, sw_config, tools, machine_name)
      end
    end

    private

    def sw_config_key(name, arch)
      "#{name}:#{normalize_arch(arch)}"
    end

    def sw_config_for(name, arch)
      config = @sw_configs[sw_config_key(name, arch)]
      return config if config

      @logger.warn("SW #{name}: no prepared config for arch #{arch}")
      nil
    end

    def config_path_candidates(name, kit, arch)
      kit_name = kit.downcase
      base = Pathname.new(@ext_path).join(name)
      candidates = []

      variants = arch_variants(arch)
      candidates += variants.map { |arch_name| base.join("#{kit_name}-#{arch_name}-config.json") }
      candidates += variants.map { |arch_name| base.join("#{arch_name}-config.json") }
      candidates += [base.join("#{kit_name}-config.json"), base.join('config.json')]

      candidates
    end

    def arch_variants(arch)
      arch_name = arch.to_s.downcase
      variants = [arch_name]
      variants << 'x64' if arch_name == 'amd64'
      variants << 'amd64' if arch_name == 'x64'
      variants.uniq
    end

    def normalize_arch(arch)
      arch.to_s.downcase
    end

    def platform_arches(include_studio: false)
      platform = @project.engine_platform
      arches = []
      arches << Project::DEFAULT_ARCH if include_studio
      arches << platform.client_arch if platform.client_arch
      platform.clients.each_value do |client|
        arches << client.arch if client.arch
      end

      arches = [Project::DEFAULT_ARCH] if arches.empty?
      arches.map { |arch| normalize_arch(arch) }.uniq
    end

    def machine_arch(machine_name)
      platform = @project.engine_platform
      client = platform.clients.values.find { |c| c.name.casecmp?(machine_name) }
      arch = client&.arch || platform.client_arch || Project::DEFAULT_ARCH
      normalize_arch(arch)
    end
  end
end
