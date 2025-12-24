# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # QemuHCK class
  class QemuHCK
    extend AutoloadExtension

    autoload_relative :Ns, 'ns'

    include Helper

    attr_reader :kit, :project

    QEMUHCK_INFO_LOG_FILE = 'qemuhck.txt'
    OPT_NAMES = %w[viommu_state s3_state s4_state enlightenments_state vhost_state machine_type fw_type cpu
                   ctrl_net_device vbs_state].freeze

    def initialize(project)
      initialize_project project

      @clients_vm = {}
      initialize_studio_vm
      initialize_clients_vm
      create_qemuhck_log_file
    end

    def initialize_project(project)
      @project = project

      @id = project.id
      @workspace_path = project.workspace_path
      @logger = project.logger

      @drivers = project.engine.drivers
      @platform = project.engine_platform

      @devices = @drivers&.map(&:device)
      @kit = @platform['kit']
    end

    def studio_vm_options
      {
        'id' => @id.to_i,
        'client_id' => 0,
        'workspace_path' => @workspace_path,
        'image_name' => @platform['st_image'],
        'logger' => @logger,
        'iso_path' => @project.config['iso_path'],
        'share_on_host_path' => @project.options.common.share_on_host_path,
        'attach_debug_net' => @project.options.common.attach_debug_net
      }.merge(platform_options)
    end

    def initialize_studio_vm
      @studio_vm = QemuMachine.new(studio_vm_options)
    end

    def drivers_options
      options = {}
      @drivers&.each do |driver|
        OPT_NAMES.each do |name|
          # We should check that driver has the requested option.
          # OPT_NAMES contains options from driver, platform, etc.
          # So, it is normal that drivers do not have all the options.
          options[name] = driver.send(name) if driver.respond_to?(name) && !driver.send(name).nil?
        end
      end
      options
    end

    def platform_options
      options = {}
      OPT_NAMES.each do |name|
        options[name] = @platform[name] unless @platform[name].nil?
      end
      options
    end

    def platform_client_options
      options = platform_options
      OPT_NAMES.each do |name|
        options[name] = @platform.dig('clients_options', name) unless @platform.dig('clients_options', name).nil?
      end
      options
    end

    def client_vm_common_options
      common = @project.options.common
      {
        'id' => @id.to_i,
        'workspace_path' => @workspace_path,
        'devices_list' => @devices,
        'logger' => @logger,
        'iso_path' => @project.config['iso_path'],
        'client_world_net' => common.client_world_net,
        'attach_debug_net' => common.attach_debug_net,
        'share_on_host_path' => common.share_on_host_path,
        'boot_device' => @project.options.test.boot_device,
        'fs_test_image_format' => @project.options.test.fs_test_image_format,
        'ctrl_net_device' => common.client_ctrl_net_dev
      }.compact
    end

    def initialize_clients_vm
      options = drivers_options.merge(platform_client_options)
      @platform['clients'].each_with_index do |(_k, v), i|
        vm_options = options.merge({
          'client_id' => i + 1,
          'image_name' => v['image'],
          'cpu_count' => v['cpus'],
          'memory_gb' => v['memory_gb']
        }.merge(client_vm_common_options))
        @clients_vm[v['name']] = QemuMachine.new(vm_options)
      end
    end

    def create_qemuhck_log_file
      qemuhck_log = "#{@workspace_path}/#{QEMUHCK_INFO_LOG_FILE}"
      File.write(qemuhck_log, collect_environment_info)
      @project.result_uploader.upload_file(qemuhck_log, QEMUHCK_INFO_LOG_FILE)
    end

    def collect_environment_info
      logs = String.new
      append_host_info(logs)
      append_vms_info(logs)
      logs.freeze
    end

    def hypervisor_info
      `#{@studio_vm.config['qemu_bin']} --version`.lines.first.strip
    end

    def host_info
      `uname -a`.strip
    end

    def append_host_info(logs)
      logs << <<~HOST_INFO
        QEMU version: #{hypervisor_info}
        System information: #{host_info}

      HOST_INFO
    end

    def append_vms_info(logs)
      logs << <<~STUDIO_INFO
        Studio Properties:
          #{@studio_vm.dump_config}
      STUDIO_INFO
      @platform['clients'].each_with_index do |(_k, v), i|
        logs << <<~CLIENT_INFO
          Client #{i + 1} Properties:
            #{@clients_vm[v['name']].dump_config}
        CLIENT_INFO
      end
    end

    def client_post_start_commands
      @clients_vm.each_value.first.post_start_commands
    end

    def check_studio_image_exist
      @studio_vm.check_image_exist
    end

    def create_studio_image
      @studio_vm.create_image
    end

    def check_client_image_exist(name)
      @clients_vm[name].check_image_exist
    end

    def create_client_image(name)
      @clients_vm[name].create_image
    end

    def studio_option_config(option)
      @studio_vm.option_config(option)
    end

    def client_option_config(name, option)
      @clients_vm[name].option_config(option)
    end

    def run_studio(scope, run_opts = nil)
      @studio_vm.run(scope, run_opts)
    end

    def run_client(scope, name, run_opts = nil)
      @clients_vm[name].run(scope, run_opts)
    end

    def run_hck_studio(scope, run_opts)
      HCKStudio.new(self, scope, run_opts) { @studio_vm.find_world_ip }
    end

    def run_hck_client(scope, studio, name, run_opts)
      HCKClient.new(self, scope, studio, name, run_opts)
    end

    def self.enter(workspace_path)
      Ns.enter workspace_path, Dir.pwd, 'bin/auto_hck', '-w',
               workspace_path, *ARGV
    end
  end
end
