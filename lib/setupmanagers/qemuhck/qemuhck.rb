# frozen_string_literal: true

require './lib/exceptions'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'
require './lib/setupmanagers/qemuhck/qemu_machine'

# AutoHCK module
module AutoHCK
  # QemuHCK class
  class QemuHCK
    include Helper

    attr_reader :kit

    OPT_NAMES = %w[viommu enlightenments_state vhost_state machine_type fw_type].freeze
    STUDIO = 'st'

    def initialize(project)
      @project = project

      @id = project.id
      @workspace_path = project.workspace_path
      @logger = project.logger

      @drivers = project.engine.drivers
      @platform = project.engine.platform

      @devices = @drivers&.map { |driver| driver['device'] }
      @kit = @platform['kit']

      @clients_vm = {}
      initialize_studio_vm
      initialize_clients_vm
    end

    def initialize_studio_vm
      @studio_vm = QemuMachine.new({
                                     'id' => @id.to_i,
                                     'client_id' => 0,
                                     'workspace_path' => @workspace_path,
                                     'image_name' => @platform['st_image'],
                                     'logger' => @logger,
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

    def initialize_clients_vm
      options = drivers_options.merge(platform_options)
      @platform['clients'].each_with_index do |(_k, v), i|
        vm_options = options.merge({
                                     'id' => @id.to_i,
                                     'client_id' => i + 1,
                                     'workspace_path' => @workspace_path,
                                     'image_name' => v['image'],
                                     'cpu_count' => v['cpus'],
                                     'memory' => v['memory'],
                                     'devices_list' => @devices,
                                     'logger' => @logger,
                                     'iso_path' => @project.config['iso_path']
                                   })
        @clients_vm[v['name']] = QemuMachine.new(vm_options)
      end
    end

    def check_studio_image_exist
      @studio_vm.check_image_exist
    end

    def create_studio_image
      @studio_vm.create_image
    end

    def create_studio_snapshot
      @studio_vm.create_snapshot
    end

    def delete_studio_snapshot
      @studio_vm.delete_snapshot
    end

    def check_client_image_exist(name)
      @clients_vm[name].check_image_exist
    end

    def create_client_image(name)
      @clients_vm[name].create_image
    end

    def create_client_snapshot(name)
      @clients_vm[name].create_snapshot
    end

    def delete_client_snapshot(name)
      @clients_vm[name].delete_snapshot
    end

    def studio_option_config(option)
      @studio_vm.option_config(option)
    end

    def client_option_config(name, option)
      @clients_vm[name].option_config(option)
    end

    def run(name, run_opts = nil)
      if name == STUDIO
        @studio_vm.run(run_opts)
      else
        @clients_vm[name].run(run_opts)
      end
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

    def create_studio
      @studio = HCKStudio.new(@project, self) { @studio_vm.read_world_ip }
    end

    def create_client(name)
      HCKClient.new(@project, self, @studio, name)
    end
  end
end
