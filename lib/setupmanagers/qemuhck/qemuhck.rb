# frozen_string_literal: true

require './lib/exceptions'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/setupmanagers/qemuhck/slirp'
require './lib/setupmanagers/qemuhck/qemu_machine'

# AutoHCK module
module AutoHCK
  # QemuHCK class
  class QemuHCK
    include Helper

    attr_reader :kit, :project

    OPT_NAMES = %w[viommu_state s3_state s4_state enlightenments_state vhost_state machine_type fw_type cpu
                   pluggable_memory_gb].freeze

    def initialize(project)
      initialize_project project

      @slirp = Slirp.new(ENV.fetch('AUTOHCK_SLIRP'))
      @clients_vm = {}
      initialize_studio_vm
      initialize_clients_vm
    end

    def initialize_project(project)
      @project = project

      @id = project.id
      @workspace_path = project.workspace_path
      @logger = project.logger

      @drivers = project.engine.drivers
      @platform = project.engine.platform

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
        'slirp' => @slirp,
        'iso_path' => @project.config['iso_path'],
        'share_on_host_path' => @project.options.common.share_on_host_path
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

    def boot_device
      return {} if @project.options.test.boot_device.nil?

      { 'boot_device' => @project.options.test.boot_device }
    end

    def client_vm_common_options
      {
        'id' => @id.to_i,
        'workspace_path' => @workspace_path,
        'devices_list' => @devices,
        'logger' => @logger,
        'slirp' => @slirp,
        'iso_path' => @project.config['iso_path'],
        'client_world_net' => @project.options.common.client_world_net,
        'share_on_host_path' => @project.options.common.share_on_host_path
      }.merge(boot_device)
    end

    def initialize_clients_vm
      options = drivers_options.merge(platform_options)
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
  end
end
