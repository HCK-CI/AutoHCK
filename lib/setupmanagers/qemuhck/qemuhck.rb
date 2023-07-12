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

    attr_reader :kit

    OPT_NAMES = %w[viommu_state enlightenments_state vhost_state machine_type fw_type cpu].freeze

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

      @devices = @drivers&.map { |driver| driver['device'] }
      @kit = @platform['kit']
    end

    def initialize_studio_vm
      @studio_vm = QemuMachine.new({
                                     'id' => @id.to_i,
                                     'client_id' => 0,
                                     'workspace_path' => @workspace_path,
                                     'image_name' => @platform['st_image'],
                                     'logger' => @logger,
                                     'slirp' => @slirp,
                                     'iso_path' => @project.config['iso_path']
                                   })
    end

    def drivers_options
      options = {}
      @drivers&.each do |driver|
        OPT_NAMES.each do |name|
          options[name] = driver[name] unless driver[name].nil?
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
      base = {
        'id' => @id.to_i,
        'workspace_path' => @workspace_path,
        'devices_list' => @devices,
        'logger' => @logger,
        'slirp' => @slirp,
        'iso_path' => @project.config['iso_path'],
        'client_world_net' => @project.options.common.client_world_net
      }.merge(boot_device)

      mode = @project.options.mode
      fw_type = @platform["#{mode}_fw_type"]
      unless fw_type.nil?
        @logger.warn(
          "Platform has #{mode}_fw_type = #{fw_type}, force to use it instead of #{base['fw_type']}"
        )
        base['fw_type'] = fw_type
      end

      base
    end

    def initialize_clients_vm
      options = drivers_options.merge(platform_options)
      @platform['clients'].each_with_index do |(_k, v), i|
        vm_options = options.merge({
          'client_id' => i + 1,
          'image_name' => v['image'],
          'cpu_count' => v['cpus'],
          'memory' => v['memory']
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

    def run_studio(run_opts = nil)
      @studio_vm.run(run_opts)
    end

    def run_client(name, run_opts = nil)
      @clients_vm[name].run(run_opts)
    end

    def studio_alive?
      @studio_vm.alive?
    end

    def client_alive?(name)
      @clients_vm[name].alive?
    end

    def keep_studio_alive
      @studio_vm.keep_alive
    end

    def keep_client_alive(name)
      @clients_vm[name].keep_alive
    end

    def clean_last_studio_run
      @studio_vm.clean_last_run
    end

    def clean_last_client_run(name)
      @clients_vm[name].clean_last_run
    end

    def abort_studio
      @logger.info('Aborting studio VM')
      @studio_vm&.close
    end

    def abort_client(name)
      @logger.info("Aborting client #{name} VM")
      @clients_vm[name]&.close
    end

    def close
      @clients_vm.each { |_k, vm| vm.close }
      if @studio.nil?
        @studio_vm&.close
      else
        @studio.abort
      end
    end

    def run_hck_studio(run_opts)
      @studio = HCKStudio.new(@project, self, run_opts) { @studio_vm.find_world_ip }
    end

    def run_hck_client(name, run_opts)
      HCKClient.new(@project, self, @studio, name, run_opts)
    end
  end
end
