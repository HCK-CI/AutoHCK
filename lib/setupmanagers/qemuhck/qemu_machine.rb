# frozen_string_literal: true

require 'tempfile'
require 'mono_logger'

require_relative './network_manager'
require_relative './monitor'
require_relative './exceptions'

require_relative '../../auxiliary/json_helper'
require_relative '../../auxiliary/host_helper'
require_relative '../../auxiliary/string_helper'

# AutoHCK module
module AutoHCK
  # QemuMachine class
  class QemuMachine
    include Helper

    MONITOR_BASE_PORT = 10_000
    VNC_BASE_PORT = 5900
    MAX_RUN_ID = 999
    MAX_CLIENT_ID = 2

    DEFAULT_RUN_OPTIONS = {
      first_time: false,
      create_snapshot: true,
      attach_iso_list: []
    }.freeze

    MACHINE_JSON = 'lib/setupmanagers/qemuhck/machine.json'
    FW_JSON = 'lib/setupmanagers/qemuhck/fw.json'
    DEVICES_JSON_DIR = 'lib/setupmanagers/qemuhck/devices'
    CONFIG_JSON = 'lib/setupmanagers/qemuhck/qemu_machine.json'
    STATES_JSON = 'lib/setupmanagers/qemuhck/states.json'

    # machine soft abort trials before force abort
    SOFT_ABORT_RETRIES = 3
    # machine abort sleep for each trial
    ABORT_SLEEP = 30

    def initialize(options)
      define_local_variables

      load_options(options)
      init_config
      apply_states
      init_ports

      @monitor = Monitor.new(@run_name, @monitor_port, @logger)

      @base_image_path = Pathname.new(@config['images_path']).join(@options['image_name'])

      @nm = NetworkManager.new(@id, @client_id, @machine, @logger)
    end

    def define_local_variables
      @devices_list = []
      @pre_start_commands = []
      @post_stop_commands = []
      @device_commands = []
      @machine_extra_param = []
      @device_extra_param = []
      @cpu_options = []
      @drive_cache_options = []
      @define_variables = {}
      @run_opts = {}

      @pid = nil
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
      port_offset = (MAX_CLIENT_ID + 1) * (@options['id'] - 1) + @options['client_id']
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
        next if state[state_value.to_s].nil?

        state[state_value.to_s].each do |key, value|
          var = :"@#{key}"
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

      @devices_list << option_config('boot_device')
      @machine_name = option_config('machine_type')
      @fw_name = option_config('fw_type')
      @machine = read_machine
      @fw = load_fw
    end

    def config_replacement_list
      {
        '@qemu_bin@' => @config['qemu_bin'],
        '@qemu_img_bin@' => @config['qemu_img_bin'],
        '@ivshmem_server_bin@' => @config['ivshmem_server_bin'],
        '@fs_daemon_bin@' => @config['fs_daemon_bin'],
        '@fs_daemon_share_path@' => @config['fs_daemon_share_path'],
        '@fs_test_image@' => @config['fs_test_image']
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
        '@cpu_count@' => option_config('cpu_count'),
        '@cpu_model@' => option_config('cpu_model'),
        '@vnc_id@' => @vnc_id,
        '@vnc_port@' => @vnc_port,
        '@qemu_monitor_port@' => @monitor_port,
        '@pid_file@' => @pid_file&.path,
        '@image_path@' => image_path
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
      @device_commands.flatten!
      @device_commands.compact!

      @machine_extra_param.flatten!
      @machine_extra_param.compact!

      @device_extra_param.flatten!
      @device_extra_param.compact!

      @pre_start_commands.flatten!
      @pre_start_commands.compact!

      @post_stop_commands.flatten!
      @post_stop_commands.compact!

      @cpu_options.flatten!
      @cpu_options.compact!

      @drive_cache_options.flatten!
      @drive_cache_options.compact!
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
        @device_commands << @nm.test_device_command(device_info['name'], full_replacement_list)
      else
        cmd = device_info['command_line'].join(' ')
        @device_commands << replace_string_recursive(cmd, full_replacement_list)
      end
    end

    def process_optional_hck_network
      return unless @config['transfer_net_enabled']

      @device_commands << @nm.transfer_device_command(@config['transfer_net_device'],
                                                      @config['share_on_host_net'],
                                                      @config['share_on_host_path'],
                                                      full_replacement_list)
    end

    def process_hck_network
      @device_commands << @nm.control_device_command(option_config('ctrl_net_device'),
                                                     full_replacement_list)

      return unless @options['client_id'].zero?

      @nm.disable_bridge_nf

      @device_commands << @nm.world_device_command(option_config('world_net_device'),
                                                   @config['world_net_bridge'],
                                                   full_replacement_list)

      process_optional_hck_network
    end

    def process_devices
      @device_commands = []
      device_infos = []

      @devices_list.each do |device|
        device_info = read_device(device)
        device_infos << device_info
        load_device_info(device_info)
      end

      unless device_infos.any? { |d| d['type'] == 'vga' }
        vga_info = read_device(@config['platforms_defaults']['vga_device'])
        device_infos << vga_info
        load_device_info(vga_info)
      end

      process_hck_network

      device_infos.each do |device_info|
        process_device(device_info)
      end
    end

    def base_cmd
      '@qemu_bin@ -enable-kvm -machine @machine_name@@machine_extra_param@ ' \
      '-m @memory@ -smp @cpu_count@,cores=@cpu_count@ ' \
      '-cpu qemu64,+x2apic,+fsgsbase@cpu_options@,model=@cpu_model@ -boot order=cd,menu=on ' \
      '-nodefaults -no-user-config -usb -device usb-tablet -vnc :@vnc_id@ ' \
      '-global kvm-pit.lost_tick_policy=discard -rtc base=localtime,clock=host,driftfix=slew ' \
      '-global @disable_s3_param@=@disable_s3_value@ -global @disable_s4_param@=@disable_s4_value@ ' \
      '-monitor telnet::@qemu_monitor_port@,server,nowait -monitor vc -pidfile @pid_file@'
    end

    def fw_cmd
      cmd = []

      cmd << "-drive if=pflash,format=raw,readonly,file=#{@fw['binary']}" if @fw['binary']
      cmd << "-drive if=pflash,format=raw,file=#{@fw['nvram']}" if @fw['nvram']

      cmd
    end

    def dirty_command
      [
        base_cmd,
        *fw_cmd,
        @machine['machine_uuid'],
        @machine['pcie_root_port'],
        *@device_commands,
        *iso_cmd,
        "-name #{@run_name}"
      ].compact
    end

    def retrieve_pid
      Timeout.timeout(10) do
        sleep 1 while File.zero?(@pid_file.path)
      end
      @pid_file.read.strip.to_i
    rescue Timeout::Error
      nil
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
        '   VM image ................... @image_path@',
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
      File.open(file_name, 'w') { |f| f.write(file_content) }
      FileUtils.chmod(0o755, file_name)
    end

    def save_run_script(file_name, file_content)
      file_path = Pathname.new(@workspace_path).join(file_name)
      create_run_script(file_path, file_content)
    end

    def run_vm
      dump_config

      @pid_file = Tempfile.new(@run_name)

      cmd = replace_string_recursive(dirty_command.join(' '), full_replacement_list)

      Thread.new do
        run_cmd([cmd])
      end
      sleep 5
      @pid = retrieve_pid

      if @pid.nil?
        @logger.error("#{@run_name} is not alive")
        raise MachineRunError, "Could not start #{@run_name}"
      end

      @logger.info("#{@run_name} started with PID #{@pid}")

      @pid
    end

    def run_pre_start_commands
      @pre_start_commands.each do |dirty_cmd|
        cmd = replace_string_recursive(dirty_cmd, full_replacement_list)
        run_cmd([cmd])
      end
    end

    def run_post_stop_commands
      @post_stop_commands.each do |dirty_cmd|
        cmd = replace_string_recursive(dirty_cmd, full_replacement_list)
        run_cmd_no_fail([cmd])
      end
    end

    def snapshot_path
      filename = File.basename(@base_image_path, '.*')
      "#{@workspace_path}/#{filename}-snapshot.qcow2"
    end

    def check_image_exist
      File.exist?(@base_image_path)
    end

    def create_image
      run_cmd(["#{@config['qemu_img_bin']} create -f qcow2", @base_image_path, '150G'])
    end

    def create_snapshot
      @logger.info("Creating #{@run_name} snapshot file")
      run_cmd(["#{@config['qemu_img_bin']} create -f qcow2 -F qcow2 -b", @base_image_path, snapshot_path])
    end

    def delete_snapshot
      FileUtils.rm_f(snapshot_path)
    end

    def image_path
      @run_opts[:create_snapshot] ? snapshot_path : @base_image_path
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

    def run(run_opts = nil)
      @run_opts = validate_run_opts(run_opts.to_h)
      create_snapshot if @run_opts[:create_snapshot]

      @devices_list.flatten!
      @devices_list.compact!

      process_devices
      normalize_lists
      run_pre_start_commands
      run_vm
    end

    def alive?
      return false if @pid.nil?

      Process.kill(0, @pid)
      true
    rescue Errno::ESRCH
      @logger.info("#{@run_name} is not alive")
      false
    end

    def keep_alive
      return if alive?

      @logger.info("Starting #{@run_name}")
      @pid = run_vm
      e_message = "New PID for #{@run_name} could not be retrieved"
      raise MachineRunError, e_message if @pid.nil?

      @logger.info("#{@run_name} new PID is #{@pid}")
      raise MachineRunError, "Could not start #{@run_name}" unless alive?
    end

    def soft_abort
      SOFT_ABORT_RETRIES.times do
        @monitor.powerdown
        sleep ABORT_SLEEP

        return true unless alive?

        @logger.debug("Powerdown was sent, but #{@run_name} is still alive :(")
      end
      false
    end

    def hard_abort
      @monitor.quit

      sleep ABORT_SLEEP
      return true unless alive?

      @logger.debug("Quit was sent, but #{@run_name} is still alive :(")
      false
    end

    def vm_abort
      return unless alive?

      return if soft_abort

      @logger.info("#{@run_name} soft abort failed, hard aborting...")

      return if hard_abort

      @logger.info("#{@run_name} hard abort failed, force aborting...")

      Process.kill('KILL', @pid)
    end

    def clean_last_run
      return if @pid.nil?

      @logger.info("Cleaning last #{@run_name} run")
      vm_abort
      delete_snapshot
    end

    def close
      vm_abort
      @nm.close
      run_post_stop_commands
    end
  end
end
