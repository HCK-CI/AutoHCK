# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # HCKClient class
  class HCKClient
    # Client cooldown timeout in seconds, to prevent hangs (30 minutes)
    CLIENT_COOLDOWN_TIMEOUT = 1800

    # Client cooldown sleep after thread is joined in seconds
    CLIENT_COOLDOWN_SLEEP = 60

    attr_reader :name, :kit, :target, :replacement_map

    def initialize(setup_manager, scope, studio, name, run_opts)
      @project = setup_manager.project
      @logger = @project.logger
      @studio = studio
      @name = name
      @kit = setup_manager.kit
      @logger.info("Starting client #{name}")
      @runner = setup_manager.run_client(scope, @name, run_opts)
      scope << self
      @setup_manager = setup_manager
      @replacement_map = ReplacementMap.new
    end

    def pool
      @studio.list_pools.each do |pool|
        return pool['name'] if pool['machines'].any? { |machine| machine['name'].eql?(@name) }
      end
    end

    def keep_snapshot
      @runner.keep_snapshot
    end

    def add_target_to_project
      @target = Targets.new(self, @project, @tools, pool).add_target_to_project
    end

    def configure_machine
      @logger.info("Configuring client #{@name}...")
      reset_to_ready_state
      sleep CLIENT_COOLDOWN_SLEEP
    end

    def reconfigure_machine
      delete_machine
      restart_machine
      return_when_client_up
      move_machine_to_pool
      configure_machine
    end

    def delete_machine
      @tools.delete_machine(@name, pool)
    end

    def restart_machine
      @logger.info("Restarting #{@name}")
      @tools.restart_machine(@name)
    end

    def move_machine_to_pool
      @logger.info("Moving #{@name} to pool")
      @tools.move_machine(@name, pool, @project.engine_tag)
    end

    def set_machine_ready
      @logger.info("Setting #{@name} state to Ready")
      return if @tools.set_machine_ready(@name, pool)

      raise ClientRunError, "Couldn't set #{@name} state to Ready"
    end

    def post_start_commands
      (@project.engine.drivers.flat_map(&:post_start_commands) +
        @setup_manager.client_post_start_commands).select(&:guest_run)
    end

    def run_post_start_commands
      post_start_commands&.each do |command|
        desc = command.desc
        @logger.info("Running command (#{desc}) on client #{@name}")
        updated_command = @replacement_map.create_cmd(command.guest_run)
        @logger.debug("Running command after replacement (#{desc}) on client #{@name}: #{updated_command}")

        @tools.run_on_machine(@name, desc, updated_command)
        next unless command.guest_reboot

        @logger.info("Rebooting client #{@name} after command (#{desc})")
        @tools.restart_machine(@name)
        reconfigure_machine
      end
    end

    def install_driver(driver)
      path = @project.options.test.driver_path
      method = driver.install_method.to_s
      inf = driver.inf

      @logger.info("Installing #{method} driver #{inf} in #{@name}")
      @tools.install_machine_driver_package(@name, method, path, inf,
                                            custom_cmd: driver.install_command,
                                            sys_file: driver.sys,
                                            force_install_cert: driver.install_cert)
    end

    def insert_driver_replacement(driver, one_driver, replacement)
      client_replacement = replacement.transform_keys { |k| k.dup.insert(1, "#{driver.short}.") }
      @replacement_map.merge!(client_replacement)

      # If there is only one driver, we can use generic keys without driver short name.
      return unless one_driver

      @replacement_map.merge!({ '@driver_short_name@' => driver.short })
      @replacement_map.merge!(replacement)
    end

    def install_drivers
      one_driver = @project.engine.drivers.one?

      @project.engine.drivers&.each do |driver|
        if driver.install_method == AutoHCK::Models::DriverInstallMethods::NoDrviver
          @project.logger.info("Driver installation skipped for #{driver.name} in #{@name}")
          next
        end

        driver_replacement = install_driver(driver)
        insert_driver_replacement(driver, one_driver, driver_replacement)
      end

      @logger.debug("Driver replacement list: #{@replacement_map.dump_string}")
    end

    def copy_dvl
      path = @project.options.test.driver_path

      @logger.info('Looking for DVL logs')
      Dir.glob("#{path}/*.DVL.XML", File::FNM_CASEFOLD).each do |dvl_file|
        dvl_file_name = File.basename(dvl_file)
        @logger.info("Uploading #{dvl_file_name} log to #{@name}")
        @tools.upload_to_machine(@name, dvl_file, "C:/DVL/#{dvl_file_name}")
      end
    end

    def machine_info
      @studio.list_pools.flat_map { |pool| pool['machines'] }
             .detect { |machine| machine['name'].eql?(@name) }
    end

    def recognize_client_wait
      @logger.info("Waiting for client #{@name} to be recognized in Default Pool")
      sleep 5 until pool == 'Default Pool'
      @logger.info("Client #{@name} recognized")
    end

    def initialize_client_wait
      @logger.info("Waiting for client #{@name} initialization")
      sleep 5 while machine_info['state'].eql?('Initializing')
      @logger.info("Client #{@name} initialized")
    end

    def return_when_client_up
      recognize_client_wait
      initialize_client_wait
    end

    def prepare_machine
      @logger.info("Preparing client #{@name}...")
      @project.extra_sw_manager.install_software_before_driver(@tools, @name)
      install_drivers
      copy_dvl
      @project.extra_sw_manager.install_software_after_driver(@tools, @name)
    end

    def configure(run_only: false)
      @tools = @studio.tools
      @cooldown_thread = Thread.new do
        unless pool == @project.engine_tag
          return_when_client_up
          if run_only
            @logger.info("Preparing client skipped #{@name}...")

            Thread.exit
          end
          prepare_machine
          move_machine_to_pool
        end

        configure_machine
        run_post_start_commands
        add_target_to_project
      end
    end

    def synchronize
      return unless @cooldown_thread&.join(CLIENT_COOLDOWN_TIMEOUT).nil?

      e_message = "Timeout expired for the cooldown thread of client #{@name}"
      raise ClientRunError, e_message
    end

    def not_ready?
      machine_info['state'].eql?('NotReady')
    end

    def reset_to_ready_state
      return unless not_ready?

      @logger.info("Setting client #{@name} state to Ready")
      set_machine_ready
    end

    def close
      @logger.info("Exiting HLKClient #{@name}")
      @cooldown_thread&.exit
    end
  end
end
