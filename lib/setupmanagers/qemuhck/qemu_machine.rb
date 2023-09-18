# frozen_string_literal: true

require 'mono_logger'

require_relative 'network_manager'
require_relative 'storage_manager'
require_relative 'qmp'
require_relative 'exceptions'

require_relative '../../auxiliary/json_helper'
require_relative '../../auxiliary/host_helper'
require_relative '../../auxiliary/resource_scope'
require_relative '../../auxiliary/string_helper'

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    # Hostfwd is a class that holds ports forwarded for a run.
    class Hostfwd
      def initialize(slirp, ports)
        @slirp = slirp
        @ids = []
        begin
          ports.each do |port|
            @ids << slirp.run({
                                'execute' => 'add_hostfwd',
                                'arguments' => {
                                  'proto' => 'tcp',
                                  'host_port' => port,
                                  'guest_port' => port
                                }
                              })
          end
        rescue StandardError
          close
        end
      end

      def close
        @ids.each do |id|
          @slirp.run({
                       'execute' => 'remove_hostfwd',
                       'arguments' => id
                     })
        end

        @ids.clear
      end
    end

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
        @qmp = QMP.new(scope, @run_name, @logger)
        @machine.run_config_commands
        run_vm
        scope << self
      end

      def keep_snapshot
        @delete_snapshot = false
      end

      def run_qemu
        @logger.info("Starting #{@run_name}")
        cmd = replace_string_recursive(@machine.dirty_command.join(' '), @machine.full_replacement_list)
        cmd += " -chardev socket,id=qmp,fd=#{@qmp.socket.fileno},server=off -mon chardev=qmp,mode=control"
        qemu = CmdRun.new(@logger, cmd, { @qmp.socket.fileno => @qmp.socket.fileno })
        @logger.info("#{@run_name} started with PID #{qemu.pid}")
        qemu
      end

      def run_vm
        @machine.dump_config

        @qemu_thread = Thread.new do
          loop do
            qemu = nil
            Thread.handle_interrupt(Object => :on_blocking) do
              @machine.run_pre_start_commands

              qemu = run_qemu
              qemu.wait_no_fail
              qemu = nil
            ensure
              unless qemu.nil?
                Process.kill 'KILL', qemu.pid
                qemu.wait_no_fail
              end
              @machine.run_post_stop_commands
            end

            break unless @keep_alive
          end
        end
      end

      def wait(...)
        @qemu_thread.join(...)
      end

      def soft_abort
        SOFT_ABORT_RETRIES.times do
          @qmp.powerdown

          return true unless @qemu_thread.join(ABORT_SLEEP).nil?

          @logger.debug("Powerdown was sent, but #{@run_name} is still alive :(")
        end
        false
      end

      def hard_abort
        @qmp.quit

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

    MONITOR_BASE_PORT = 10_000
    VNC_BASE_PORT = 5900
    MAX_RUN_ID = 999
    MAX_CLIENT_ID = 2

    DEFAULT_RUN_OPTIONS = {
      keep_alive: false,
      first_time: false,
      create_snapshot: true,
      attach_iso_list: [],
      dump_only: false
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
      apply_states
      init_ports

      @nm = NetworkManager.new(@id, @client_id, @machine, @logger)
      @sm = StorageManager.new(@id, @client_id, @config, @options, @logger)
    end

    def define_local_variables
      @devices_list = []
      @config_commands = []
      @pre_start_commands = []
      @post_stop_commands = []
      @device_commands = []
      @machine_extra_param = []
      @device_extra_param = []
      @iommu_device_param = []
      @cpu_options = []
      @drive_cache_options = []
      @define_variables = {}
      @run_opts = {}
    end

    def load_options(options)
      @options = options

      @logger = @options['logger'] || MonoLogger.new($stdout)

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
      res = fws[@fw_name]

      unless res
        @logger.fatal("#{@fw_name} does not exist")
        raise(InvalidConfigFile, "#{@fw_name} does not exist")
      end

      return res unless res['nvram']

      @logger.info("FW #{@fw_name} has NVRAM. Creating local copy")
      nvram = "#{@workspace_path}/#{@fw_name}_#{@id}_cl#{@client_id}.nvram"
      FileUtils.cp(res['nvram'], nvram)
      res['nvram'] = nvram

      res
    end

    def option_config(option)
      return @options[option] if @options.keys.include? option

      @config['platforms_defaults'][option]
    end

    def apply_states
      @states_config.each do |name, state|
        state_value = option_config(name)
        @logger.debug("Processing state #{name}, value #{state_value}")
        next if state[state_value.to_s].nil?

        state[state_value.to_s].each do |key, value|
          var = :"@#{key}"
          @logger.debug("State key variable #{var}")

          next unless defined? var

          case (var_value = instance_variable_get var)
          when Hash
            var_value.merge! value
          when Array
            var_value << value
          else
            raise(QemuHCKError, "Variable #{var} has unsupported type")
          end
        end
      end
    end

    def init_config
      @config = Json.read_json(CONFIG_JSON, @logger)
      @states_config = Json.read_json(STATES_JSON, @logger)

      @machine_name = option_config('machine_type')
      @fw_name = option_config('fw_type')
      @machine = read_machine
      @fw = load_fw
    end

    def config_replacement_list
      {
        '@qemu_bin@' => @config['qemu_bin'],
        '@ivshmem_server_bin@' => @config['ivshmem_server_bin'],
        '@fs_daemon_bin@' => @config['fs_daemon_bin'],
        '@fs_daemon_share_path@' => @config['fs_daemon_share_path']
      }
    end

    def machine_replacement_list
      {
        '@bus_name@' => @machine['bus_name'],
        '@ctrl_bus_name@' => @machine['ctrl_bus_name'],
        '@disable_s3_param@' => @machine['disable_s3_param'],
        '@disable_s4_param@' => @machine['disable_s4_param'],
        '@machine_name@' => @machine_name
      }
    end

    def options_replacement_list
      {
        '@machine_extra_param@' => @machine_extra_param.join,
        '@device_extra_param@' => @device_extra_param.join,
        '@iommu_device_param@' => @iommu_device_param.join,
        '@cpu_options@' => @cpu_options.join,
        '@drive_cache_options@' => @drive_cache_options.join
      }
    end

    def full_replacement_list
      {
        '@run_id@' => @id,
        '@run_id_first@' => @id_first,
        '@run_id_second@' => @id_second,
        '@client_id@' => @client_id,
        '@workspace@' => @workspace_path,
        '@memory@' => option_config('memory'),
        '@cpu@' => option_config('cpu'),
        '@cpu_count@' => option_config('cpu_count'),
        '@cpu_model@' => option_config('cpu_model'),
        '@vnc_id@' => @vnc_id,
        '@vnc_port@' => @vnc_port,
        '@qemu_monitor_port@' => @monitor_port
      }.merge(config_replacement_list)
        .merge(machine_replacement_list)
        .merge(options_replacement_list)
        .merge(@define_variables)
    end

    def read_device(device)
      @logger.info("Loading device: #{device}")
      device_json = "#{DEVICES_JSON_DIR}/#{device}.json"
      unless File.exist?(device_json)
        @logger.fatal("#{device} does not exist")
        raise(InvalidConfigFile, "#{device} does not exist")
      end
      Json.read_json(device_json, @logger)
    end

    def normalize_lists
      [@device_commands, @machine_extra_param, @device_extra_param, @iommu_device_param,
       @config_commands, @pre_start_commands, @post_stop_commands, @cpu_options,
       @drive_cache_options].each do |arr|
        arr.flatten!
        arr.compact!
      end
    end

    def load_device_info(device_info)
      device_info.each do |key, value|
        next if %w[command_line name type].include? key

        var = :"@#{key}"
        raise(QemuHCKError, "Variable #{var} is not defined") unless defined? var

        case (var_value = instance_variable_get var)
        when Hash
          var_value.merge! value
        when Array
          var_value << value
        else
          raise(QemuHCKError, "Variable #{var} has unsupported type")
        end
      end
    end

    def process_device(device_info)
      case device_info['type']
      when 'network'
        dev = @nm.test_device_command(device_info['name'], full_replacement_list)
        @device_commands << dev
      when 'storage'
        dev = @sm.test_device_command(device_info['name'], full_replacement_list)
        @device_commands << dev
      else
        cmd = device_info['command_line'].join(' ')
        @device_commands << replace_string_recursive(cmd, full_replacement_list)
      end
    end

    def process_optional_hck_network
      return unless @config['transfer_net_enabled']

      dev = @nm.transfer_device_command(@config['transfer_net_device'],
                                        @config['share_on_host_net'],
                                        @config['share_on_host_path'],
                                        full_replacement_list)
      @device_commands << dev
    end

    def process_world_hck_network
      dev = @nm.world_device_command(option_config('world_net_device'),
                                     full_replacement_list)
      @device_commands << dev
    end

    def add_missing_default_devices(device_infos)
      return if device_infos.any? { |d| d['type'] == 'vga' }

      vga_info = read_device(@config['platforms_defaults']['vga_device'])
      device_infos << vga_info
      load_device_info(vga_info)
    end

    def process_hck_network
      dev = @nm.control_device_command(option_config('ctrl_net_device'),
                                       full_replacement_list)
      @device_commands << dev

      process_optional_hck_network

      return unless @options['client_id'].zero? || option_config('client_world_net')

      process_world_hck_network
    end

    def process_storage
      dev, @image_path = @sm.boot_device_command(option_config('boot_device'), @run_opts, full_replacement_list)
      @device_commands << dev
    end

    def process_devices
      @device_commands = []
      device_infos = []

      @devices_list.each do |device|
        device_info = read_device(device)
        device_infos << device_info
        load_device_info(device_info)
      end

      add_missing_default_devices(device_infos)

      process_hck_network
      process_storage

      device_infos.each do |device_info|
        process_device(device_info)
      end
    end

    def base_cmd
      [
        '@qemu_bin@ -enable-kvm -machine @machine_name@@machine_extra_param@ ',
        '-m @memory@ -smp @cpu_count@,cores=@cpu_count@ ',
        '-cpu @cpu@,+x2apic,+fsgsbase@cpu_options@,model=@cpu_model@ -boot order=cd,menu=on ',
        '-nodefaults -no-user-config -usb -device usb-tablet -vnc :@vnc_id@ ',
        '-global kvm-pit.lost_tick_policy=discard -rtc base=localtime,clock=host,driftfix=slew ',
        '-global @disable_s3_param@=@disable_s3_value@ -global @disable_s4_param@=@disable_s4_value@ ',
        '-monitor telnet::@qemu_monitor_port@,server,nowait -monitor vc'
      ]
    end

    def fw_cmd
      cmd = []

      cmd << "-drive if=pflash,format=raw,readonly=on,file=#{@fw['binary']}" if @fw['binary']
      cmd << "-drive if=pflash,format=raw,file=#{@fw['nvram']}" if @fw['nvram']

      cmd
    end

    def dirty_command
      [
        *base_cmd,
        *fw_cmd,
        @machine['machine_uuid'],
        @machine['pcie_root_port'],
        *@device_commands,
        *iso_cmd,
        "-name #{@run_name}"
      ].compact
    end

    def find_world_ip
      @nm.find_world_ip option_config('world_net_device'), full_replacement_list
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
      @logger.info(replace_string_recursive(config.join("\n"), full_replacement_list))
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
      @config_commands.each do |dirty_cmd|
        cmd = replace_string_recursive(dirty_cmd, full_replacement_list)
        run_cmd(cmd)
      end
    end

    def run_pre_start_commands
      @pre_start_commands.each do |dirty_cmd|
        cmd = replace_string_recursive(dirty_cmd, full_replacement_list)
        run_cmd(cmd)
      end
    end

    def run_post_stop_commands
      @post_stop_commands.each do |dirty_cmd|
        cmd = replace_string_recursive(dirty_cmd, full_replacement_list)
        run_cmd_no_fail(cmd)
      end
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

    def iso_cmd
      @run_opts[:attach_iso_list]&.map do |iso|
        iso_path = Pathname.new(@options['iso_path']).join(iso)
        "-drive file=#{iso_path},media=cdrom,readonly=on"
      end
    end

    def validate_run_opts(run_opts)
      extra_keys = (run_opts.keys - DEFAULT_RUN_OPTIONS.keys)
      raise(MachineRunError, "Undefined run options: #{extra_keys.join(', ')}.") unless extra_keys.empty?

      DEFAULT_RUN_OPTIONS.merge(run_opts)
    end

    def merge_commands_array(arr)
      arr.reduce('') do |sum, dirty_cmd|
        "#{sum}#{replace_string_recursive(dirty_cmd, full_replacement_list)}\n"
      end
    end

    def dump_commands
      dump_config

      file_name = "#{@workspace_path}/#{@run_name}_manual.sh"
      content = [
        "#!/usr/bin/env bash\n",

        "\n\n# QEMU pre start commands\n",
        merge_commands_array(@pre_start_commands),

        "\n\n# QEMU command line\n",
        replace_string_recursive(dirty_command.join(" \\\n"), full_replacement_list),

        "\n\n# QEMU post stop commands\n",
        merge_commands_array(@post_stop_commands)
      ]

      create_run_script(file_name, content.join)

      return if @config_commands.empty?

      file_name = "#{@workspace_path}/#{@run_name}_config.sh"
      content = [
        "#!/usr/bin/env bash\n",

        "\n\n# QEMU config commands\n",
        merge_commands_array(@config_commands)
      ]

      create_run_script(file_name, content.join)
    end

    def run(scope, run_opts = nil)
      @run_opts = validate_run_opts(run_opts.to_h)
      @keep_alive = run_opts[:keep_alive]

      @devices_list.flatten!
      @devices_list.compact!

      process_devices
      normalize_lists

      if @run_opts[:dump_only]
        dump_commands
      else
        scope.transaction do |tmp_scope|
          hostfwd = Hostfwd.new(@options['slirp'], [@monitor_port, @vnc_port])
          tmp_scope << hostfwd
          Runner.new(tmp_scope, @logger, self, @run_name, @run_opts)
        end
      end
    end
  end
end
