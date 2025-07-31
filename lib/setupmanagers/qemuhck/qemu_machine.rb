# typed: true
# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    extend T::Sig
    extend AutoHCK::AutoloadExtension
    autoload_relative :NetworkManager, 'network_manager'
    autoload_relative :QMP, 'qmp'
    autoload_relative :StorageManager, 'storage_manager'

    # Runner is a class that represents a run.
    class Runner
      include Helper

      # machine soft abort trials before force abort
      SOFT_ABORT_RETRIES = 3
      # machine abort sleep for each trial
      ABORT_SLEEP = 30

      def initialize(scope, logger, machine, run_name, run_opts)
        @logger = logger
        @machine = machine
        @run_name = run_name
        @run_opts = run_opts
        @keep_alive = run_opts[:keep_alive]
        @delete_snapshot = run_opts[:create_snapshot]
        @logger.info(@machine.dump_config)
        @qemu_thread = Thread.new do
          loop do
            run_vm
            break unless @keep_alive
          end
        end
        scope << self
      end

      def keep_snapshot
        @delete_snapshot = false
      end

      def try_with_qmp
        yield @qmp unless @qmp.nil?
      rescue IOError
        # @qmp is closed.
      end

      def run_qemu(scope, pgroup:)
        @logger.info("Starting #{@run_name}")
        @qmp = QMP.new(scope, @run_name, @logger)
        qemu = @machine.run_qemu(scope, @qmp, pgroup:)
        @logger.info("#{@run_name} started with PID #{qemu.pid}")
        qemu
      end

      def check_fails_too_quickly(status)
        if status&.zero?
          @first_fail_time = nil
          false
        elsif @first_fail_time.nil?
          @first_fail_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          false
        else
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - @first_fail_time <= 10
        end
      end

      def run_vm
        ResourceScope.open do |scope|
          pgroup = Pgroup.new(scope).pid
          begin
            @machine.run_pre_start_commands(pgroup:)

            qemu = run_qemu(scope, pgroup:)
            begin
              fails_quickly = check_fails_too_quickly(qemu.close.exitstatus)
              raise QemuRunError, 'QEMU fails repeated too quickly' if fails_quickly
            ensure
              if qemu.status.nil?
                Process.kill 'KILL', qemu.pid
                qemu.close
              end
            end
          ensure
            @machine.run_post_stop_commands(pgroup:)
          end
        end
      end

      def wait(...)
        @qemu_thread.join(...)
      end

      def soft_abort
        SOFT_ABORT_RETRIES.times do
          try_with_qmp(&:powerdown)

          return true unless @qemu_thread.join(ABORT_SLEEP).nil?

          @logger.debug("Powerdown was sent, but #{@run_name} is still alive :(")
        end
        false
      end

      def hard_abort
        try_with_qmp(&:quit)

        return true unless @qemu_thread.join(ABORT_SLEEP).nil?

        @logger.debug("Quit was sent, but #{@run_name} is still alive :(")
        false
      end

      def vm_abort
        @keep_alive = false

        return unless @qemu_thread.alive?

        return if soft_abort

        @logger.info("#{@run_name} soft abort failed, hard aborting...")

        return if hard_abort

        @logger.info("#{@run_name} hard abort failed, force aborting...")

        @qemu_thread.kill
        @qemu_thread.join
      end

      def close
        return if @run_opts[:dump_only]

        vm_abort
        @machine.delete_snapshot if @delete_snapshot
      end
    end

    include Helper

    attr_reader :config

    MONITOR_BASE_PORT = 10_000
    VNC_BASE_PORT = 5900
    MAX_RUN_ID = 999
    MAX_CLIENT_ID = 2

    DEFAULT_RUN_OPTIONS = {
      keep_alive: false,
      first_time: false,
      create_snapshot: true,
      boot_from_snapshot: false,
      attach_iso_list: [],
      dump_only: false,
      secure: false
    }.freeze

    MACHINE_JSON = 'lib/setupmanagers/qemuhck/machine.json'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'
    DEVICES_JSON_DIR = 'lib/setupmanagers/qemuhck/devices'
    CONFIG_JSON = 'lib/setupmanagers/qemuhck/qemu_machine.json'
    STATES_JSON = 'lib/setupmanagers/qemuhck/states.json'

    def initialize(options)
      define_local_variables

      load_options(options)
      init_config
      init_ports

      @nm = NetworkManager.new(@id, @client_id, @machine, @logger)
      @sm = StorageManager.new(@id, @client_id, @config, @options, @logger)

      @devices_list.flatten!
      @devices_list.compact!
      @device_infos = load_devices
    end

    def define_local_variables
      @devices_list = []
      @device_commands = []
      @machine_options = %w[@machine_name@]
      @device_extra_param = []
      @cpu_options = %w[@cpu@ +x2apic +fsgsbase model=@cpu_model@]
      @drive_cache_options = []
      @define_variables = {}
      @run_opts = {}
      @configured = false
    end

    def load_options(options)
      @options = options

      @logger = @options['logger'] || MonoLogger.new($stderr)

      @id = format('%04d', @options['id'])
      @id_first = @id[0..1]
      @id_second = @id[2..3]
      @client_id = format('%02d', @options['client_id'])
      @run_name = "QemuMachine#{@id}_CL#{@client_id}"

      @devices_list << @options['devices_list']
      @workspace_path = @options['workspace_path']

      @devices_list.flatten!
      @devices_list.compact!
    end

    def init_ports
      port_offset = ((MAX_CLIENT_ID + 1) * (@options['id'] - 1)) + @options['client_id']
      @monitor_port = MONITOR_BASE_PORT + port_offset
      @vnc_id = 1 + port_offset
      @vnc_port = VNC_BASE_PORT + @vnc_id
    end

    def read_machine
      machines = Json.read_json(MACHINE_JSON, @logger)
      @logger.info("Loading machine: #{@machine_name}")
      res = machines[@machine_name]
      @logger.fatal("#{@machine_name} does not exist") unless res
      res || raise(InvalidConfigFile, "#{@machine_name} does not exist")
    end

    def load_fw
      fws = Json.read_json(FW_JSON, @logger)
      @logger.info("Loading FW: #{@fw_name}")
      @fw = fws[@fw_name]

      unless @fw
        @logger.fatal("#{@fw_name} does not exist")
        raise(InvalidConfigFile, "#{@fw_name} does not exist")
      end

      @machine_options << 'pflash0=pflash_code' if @fw['binary']

      return unless @fw['nvram']

      nvram = "#{@workspace_path}/#{@fw_name}_#{@id}_cl#{@client_id}.nvram"
      @logger.info("FW #{@fw_name} has NVRAM. Creating local copy #{@fw['nvram']} -> #{nvram}")
      FileUtils.cp(@fw['nvram'], nvram)
      @fw['nvram'] = nvram
      @machine_options << 'pflash1=pflash_vars'
    end

    def option_config(option)
      return @options[option] if @options.keys.include? option

      @config['platforms_defaults'][option]
    end

    def apply_state(name, state)
      state_value = option_config(name)
      @logger.debug("Processing state #{name}, value #{state_value}")

      state[state_value.to_s]&.each do |key, value|
        var = :"@#{key}"
        @logger.debug("State key variable #{var}")

        next unless defined? var

        case (var_value = instance_variable_get var)
        when Hash
          var_value.merge! value
        when Array
          var_value |= value
          instance_variable_set var, var_value
        else
          raise(QemuHCKError, "Variable #{var} has unsupported type")
        end
      end
    end

    def init_config
      @config = Json.read_json(CONFIG_JSON, @logger)

      @machine_name = option_config('machine_type')
      @fw_name = option_config('fw_type')
      @machine = read_machine
      load_fw

      states_config = Json.read_json(STATES_JSON, @logger)
      states_config.each { |name, state| apply_state name, state }
    end

    def config_replacement_map
      {
        '@qemu_bin@' => @config['qemu_bin'],
        '@ivshmem_server_bin@' => @config['ivshmem_server_bin'],
        '@fs_daemon_bin@' => @config['fs_daemon_bin'],
        '@fs_daemon_share_path@' => @config['fs_daemon_share_path'],
        '@swtpm_setup_bin@' => @config['swtpm_setup_bin'],
        '@swtpm_bin@' => @config['swtpm_bin']
      }
    end

    def machine_replacement_map
      {
        '@bus_name@' => @machine['bus_name'],
        '@ctrl_bus_name@' => @machine['ctrl_bus_name'],
        '@disable_s3_param@' => @machine['disable_s3_param'],
        '@disable_s4_param@' => @machine['disable_s4_param'],
        '@machine_name@' => @machine_name
      }
    end

    def memory_replacement_map
      memory_gb = option_config('memory_gb')

      pluggable_memory_gb = @device_infos.sum(&:pluggable_memory_gb)

      {
        '@memory@' => "#{memory_gb}G",
        '@pluggable_memory@' => "#{pluggable_memory_gb}G",
        '@max_memory@' => "#{memory_gb + pluggable_memory_gb}G"
      }
    end

    def options_replacement_map
      {
        '@machine_options@' => (@machine_options + device_machine_options).join(','),
        '@device_extra_param@' => @device_extra_param.join,
        '@iommu_device_param@' => device_iommu_device_param.join,
        '@cpu_options@' => @cpu_options.join(','),
        '@drive_cache_options@' => @drive_cache_options.join
      }
    end

    sig { returns(T::Array[String]) }
    def device_config_commands
      @device_infos.map(&:config_commands).flatten.compact
    end

    sig { returns(T::Array[String]) }
    def device_pre_start_commands
      @device_infos.map(&:pre_start_commands).flatten.compact
    end

    sig { returns(T::Array[String]) }
    def device_post_stop_commands
      @device_infos.map(&:post_stop_commands).flatten.compact
    end

    sig { returns(T::Hash[String, String]) }
    def device_define_variables
      @device_infos.map(&:define_variables).reduce({}, :merge)
    end

    sig { returns(T::Array[String]) }
    def device_machine_options
      @device_infos.map(&:machine_options).flatten.compact
    end

    sig { returns(T::Array[String]) }
    def device_iommu_device_param
      @device_infos.filter_map(&:iommu_device_param)
    end

    def full_replacement_map
      ReplacementMap.new({
                           '@run_id@' => @id,
                           '@run_id_first@' => @id_first,
                           '@run_id_second@' => @id_second,
                           '@client_id@' => @client_id,
                           '@source@' => Dir.pwd,
                           '@workspace@' => @workspace_path,
                           '@cpu@' => option_config('cpu'),
                           '@cpu_count@' => option_config('cpu_count'),
                           '@cpu_model@' => option_config('cpu_model'),
                           '@vnc_id@' => @vnc_id,
                           '@vnc_port@' => @vnc_port,
                           '@qemu_monitor_port@' => @monitor_port
                         }, config_replacement_map,
                         machine_replacement_map,
                         memory_replacement_map,
                         options_replacement_map,
                         device_define_variables,
                         @define_variables)
    end

    def read_dynamic_device(device)
      begin
        device_path = Pathname.new(DEVICES_JSON_DIR).join("#{device}.rb").realpath
      rescue Errno::ENOENT
        return nil
      end

      require device_path.to_s

      raise InvalidConfigFile, "#{device} does not exist" unless QemuHCK::Devices.respond_to?(device)

      QemuHCK::Devices.public_send(device, @logger)
    end

    sig { params(device: String).returns(Models::QemuHCKDevice) }
    def read_device(device)
      @logger.info("Loading device: #{device}")

      dynamic_device = read_dynamic_device(device)
      return dynamic_device if dynamic_device

      Models::QemuHCKDevice.from_json_file("#{DEVICES_JSON_DIR}/#{device}.json", @logger)
    end

    def normalize_lists
      [@device_commands, @machine_options, @device_extra_param,
       @cpu_options, @drive_cache_options].each do |arr|
        arr.flatten!
        arr.compact!
      end
    end

    sig { params(device_info: Models::QemuHCKDevice, bus_name: T.nilable(String)).returns(String) }
    def regular_device_command(device_info, bus_name = nil)
      replacement_map = if bus_name.nil?
                          full_replacement_map
                        else
                          full_replacement_map.merge({ '@bus_name@' => bus_name })
                        end

      dirty_cmd = device_info.command_line.join(' ')
      replacement_map.create_cmd(dirty_cmd)
    end

    sig { params(device_info: Models::QemuHCKDevice).void }
    def process_device_command(device_info)
      bus_name = @machine['bus_name']

      dev = case device_info.type
            when 'network'
              @nm.test_device_command(device_info, bus_name, full_replacement_map)
            when 'storage'
              @sm.test_device_command(device_info, full_replacement_map)
            else
              regular_device_command(device_info, bus_name)
            end

      @logger.debug("Device command: #{dev}")
      @device_commands << dev
    end

    def process_optional_hck_network
      path = @options['share_on_host_path'] || @config['share_on_host_path']
      return unless path

      device_info = read_device(@config['transfer_net_device'])
      dev = @nm.transfer_device_command(device_info,
                                        @config['share_on_host_net'],
                                        path,
                                        @machine['bus_name'],
                                        full_replacement_map)
      @device_commands << dev
    end

    def process_world_hck_network
      device_info = read_device(option_config('world_net_device'))
      dev = @nm.world_device_command(device_info, @machine['bus_name'], full_replacement_map)
      @device_commands << dev
    end

    sig { params(device_infos: T::Array[Models::QemuHCKDevice]).void }
    def add_missing_default_devices(device_infos)
      return if device_infos.any? { |d| d.type == 'vga' }

      vga_info = read_device(@config['platforms_defaults']['vga_device'])
      device_infos << vga_info
    end

    def process_hck_network_command
      device_info = read_device(option_config('ctrl_net_device'))
      dev = @nm.control_device_command(device_info, full_replacement_map)
      @device_commands << dev

      process_optional_hck_network

      return unless @options['client_id'].zero? || option_config('client_world_net')

      process_world_hck_network
    end

    def process_storage_command
      device_info = read_device(option_config('boot_device'))
      dev, @image_path = @sm.boot_device_command(device_info, @run_opts, full_replacement_map)
      @device_commands << dev

      devs = @sm.iso_commands(@run_opts, full_replacement_map)
      @device_commands << devs
    end

    sig { returns(T::Array[Models::QemuHCKDevice]) }
    def load_devices
      device_infos = @devices_list.map { |device| read_device(device) }

      add_missing_default_devices(device_infos)

      device_infos
    end

    def process_device_commands
      @device_commands = []

      process_hck_network_command
      process_storage_command

      @device_infos.each do |device_info|
        process_device_command(device_info)
      end
    end

    # With some Windows versions, we have a problem with the boot order.
    # Add boot menu timeout (splash-time) to allow us to manually workaround
    # this behavior.
    # Known affected versions: Win2022 (on PC) and Win11_24H2 (on Q35)
    def base_cmd
      [
        '@qemu_bin@ -enable-kvm -machine @machine_options@ ',
        '-m @memory@,maxmem=@max_memory@ -smp @cpu_count@,cores=@cpu_count@ ',
        '-cpu @cpu_options@ -boot menu=on,splash-time=10000 ',
        '-nodefaults -no-user-config -usb -device usb-tablet -vnc :@vnc_id@ ',
        '-global kvm-pit.lost_tick_policy=discard -rtc base=localtime,clock=host,driftfix=slew ',
        '-global @disable_s3_param@=@disable_s3_value@ -global @disable_s4_param@=@disable_s4_value@ ',
        '-monitor telnet::@qemu_monitor_port@,server,nowait -monitor vc'
      ]
    end

    def fw_cmd
      cmd = []

      if @fw['binary']
        file = @fw['binary'][@run_opts[:secure] ? 'secure' : 'insecure']
        cmd << "-blockdev node-name=pflash_code,driver=file,filename=#{file},read-only=on"
      end

      if @fw['nvram']
        cmd << "-blockdev node-name=pflash_vars,driver=file,filename=#{@fw['nvram']}"
        cmd << '-global driver=cfi.pflash01,property=secure,value=on'
      end

      cmd
    end

    def qemu_cmd
      [
        full_replacement_map.create_cmd([
          *base_cmd,
          *fw_cmd,
          @machine['machine_uuid'],
          @machine['pcie_root_port'],
          "-name #{@run_name}"
        ].compact.join(' ')),
        *@device_commands
      ].join(" \\\n")
    end

    def find_world_ip
      @nm.find_world_ip option_config('world_net_device'), full_replacement_map
    end

    def dump_config
      config = [
        'Setup configuration:',
        '   Setup ID ................... @run_id@',
        '   Machine type ............... @machine_name@',
        '   QEMU binary ................ @qemu_bin@',
        "   FW type .................... #{@fw_name}",
        "   Test devices ............... #{@devices_list.join(', ')}",
        '   VM ID ...................... @client_id@',
        "   VM image ................... #{@image_path}",
        '   VM VCPU .................... @cpu@',
        '   VM VCPUs ................... @cpu_count@',
        '   VM Memory .................. @memory@',
        '   VM pluggable memory ........ @pluggable_memory@',
        '   VM display port ............ Vnc @vnc_id@/@vnc_port@',
        '   VM monitor port ............ Telnet @qemu_monitor_port@'
      ]
      #  Test suite type............ ${TEST_DEV_TYPE}
      #  Test device................ ${TEST_DEV_NAME}
      #  Test device extra config... ${EXTRA_PARAMS}
      #  Graphics................... ${VIDEO_TYPE}
      #  Test network backend....... ${TEST_NET_TYPE}
      #  SMB share on host.......... ${SHARE_ON_HOST}
      #  Client world access........ ${CLIENT_WORLD_ACCESS_NOTIFY}
      #  World network device....... ${WORLD_NET_DEVICE}
      #  Control network device..... ${CTRL_NET_DEVICE}
      #  VHOST...................... ${VHOST_STATE}
      #  Enlightenments..............${ENLIGHTENMENTS_STATE}
      #  S3 enabled..................${ENABLE_S3}
      #  S4 enabled..................${ENABLE_S4}
      #  Snapshot mode.............. ${SNAPSHOT}
      full_replacement_map.replace(config.join("\n"))
    end

    def create_run_script(file_name, file_content)
      File.write(file_name, file_content)
      FileUtils.chmod(0o755, file_name)
    end

    def save_run_script(file_name, file_content)
      file_path = Pathname.new(@workspace_path).join(file_name)
      create_run_script(file_path, file_content)
    end

    def run_config_commands
      device_config_commands.each do |dirty_cmd|
        cmd = full_replacement_map.create_cmd(dirty_cmd)
        run_cmd(cmd)
      end
    end

    def run_pre_start_commands(pgroup:)
      Timeout.timeout(60) do
        device_pre_start_commands.each do |dirty_cmd|
          cmd = full_replacement_map.create_cmd(dirty_cmd)
          run_cmd(cmd, chdir: @workspace_path, pgroup:)
        end
      end
    end

    def run_post_stop_commands(pgroup:)
      Timeout.timeout(60) do
        device_post_stop_commands.each do |dirty_cmd|
          cmd = full_replacement_map.create_cmd(dirty_cmd)
          run_cmd(cmd, chdir: @workspace_path, exception: false, pgroup:)
        end
      end
    end

    def run_qemu(scope, qmp, pgroup:)
      cmd = qemu_cmd
      cmd += " -chardev socket,id=qmp,fd=#{qmp.socket.fileno},server=off -mon chardev=qmp,mode=control"
      CmdRun.new(scope, @logger, cmd,
                 chdir: @workspace_path, exception: false, pgroup:,
                 qmp.socket.fileno => qmp.socket.fileno)
    end

    def check_image_exist
      @sm.check_image_exist
    end

    def create_image
      @sm.create_boot_image
    end

    def delete_snapshot
      @sm.delete_boot_snapshot
    end

    def validate_run_opts(run_opts)
      extra_keys = (run_opts.keys - DEFAULT_RUN_OPTIONS.keys)
      raise(MachineRunError, "Undefined run options: #{extra_keys.join(', ')}.") unless extra_keys.empty?

      DEFAULT_RUN_OPTIONS.merge(run_opts)
    end

    def merge_commands_array(arr)
      arr.reduce('') do |sum, dirty_cmd|
        "#{sum}#{full_replacement_map.create_cmd(dirty_cmd)}\n"
      end
    end

    def dump_commands
      @logger.info(dump_config)

      file_name = "#{@workspace_path}/#{@run_name}_manual.yaml"
      content = YAML.dump(
        'cmd' => <<~BASH,
          # QEMU pre start commands
          #{merge_commands_array(device_pre_start_commands)}

          # QEMU command line
          #{qemu_cmd}

          # QEMU post stop commands
          #{merge_commands_array(device_post_stop_commands)}
        BASH
        'ports' => [@monitor_port, @vnc_port]
      )

      create_run_script file_name, <<~YAML
        #!#{File.absolute_path('bin/run_dump')}
        #{content}
      YAML

      return if device_config_commands.empty?

      file_name = "#{@workspace_path}/#{@run_name}_config.sh"
      content = [
        "#!/usr/bin/env bash\n",

        "\n\n# QEMU config commands\n",
        merge_commands_array(device_config_commands)
      ]

      create_run_script(file_name, content.join)
    end

    def run(scope, run_opts = nil)
      @run_opts = validate_run_opts(run_opts.to_h)
      @keep_alive = run_opts[:keep_alive]

      process_device_commands
      normalize_lists

      if @run_opts[:dump_only]
        dump_commands
      else
        unless @configured
          run_config_commands
          @configured = true
        end

        scope.transaction do |tmp_scope|
          hostfwd = QemuHCK::Ns::Hostfwd.new(@logger, @workspace_path, [@monitor_port, @vnc_port])
          tmp_scope << hostfwd
          Runner.new(tmp_scope, @logger, self, @run_name, @run_opts)
        end
      end
    end
  end
end
