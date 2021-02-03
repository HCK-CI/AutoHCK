# frozen_string_literal: true

require 'English'
require './lib/exceptions'
require './lib/auxiliary/json_helper'
require './lib/auxiliary/host_helper'

# Virthck class
class VirtHCK
  attr_reader :kit
  VIRTHCK_CONFIG_JSON = 'lib/setupmanagers/virthck/virthck.json'
  PLATFORMS_JSON = 'lib/engines/platforms.json'
  STUDIO = 'st'

  def initialize(project)
    @project = project
    @logger = project.logger
    @config = read_json(VIRTHCK_CONFIG_JSON, @logger)
    @device = project.driver['device']
    @platform = read_platform
    @workspace_path = project.workspace_path
    @id = project.id
    @kit = @platform['kit']
    validate_paths
  end

  def read_platform
    platforms = read_json(PLATFORMS_JSON, @project.logger)
    platform_name = @project.tag.split('-', 2).last
    @project.logger.info("Loading platform: #{platform_name}")
    res = platforms.find { |p| p['name'] == platform_name }
    @project.logger.fatal("#{platform_name} does not exist") unless res
    res || raise(SetupManagerError, "#{platform_name} does not exist")
  end

  def studio_snapshot
    filename = File.basename(@platform['st_image'], '.*')
    @workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def client_snapshot(name)
    filename = File.basename(@platform['clients'][name]['image'], '.*')
    @workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def platform_config(param)
    default_value = @config['platforms_defaults'][param]
    @platform[param] || default_value
  end

  def base_cmd
    ["cd #{@config['virthck_path']} &&",
     "sudo ./hck.sh ci_mode -id #{@id}",
     "-world_bridge #{@config['dhcp_bridge']}",
     "-qemu_bin #{@config['qemu_bin']}",
     "-ivshmem_server_bin #{@config['ivshmem_server_bin']}",
     "-fs_deamon_bin #{@config['fs_deamon_bin']}",
     "-filesystem_tests_image #{@config['filesystem_tests_image']}",
     "-ctrl_net_device #{platform_config('ctrl_net_device')}",
     "-world_net_device #{platform_config('world_net_device')}",
     "-viommu #{platform_config('viommu')}",
     "-st_image #{studio_snapshot}"]
  end

  def device_cmd
    ["-device_type #{@device['type']}",
     !@device['name'].empty? ? "-device_name #{@device['name']}" : '',
     !@device['extra'].empty? ? "-device_extra #{@device['extra']}" : '',
     "-machine_type #{platform_config('machine_type')}",
     "-s3 #{platform_config('s3')}",
     "-s4 #{platform_config('s4')}",
     "-enlightenments_state #{platform_config('enlightenments_state')}",
     "-vhost_state #{platform_config('vhost_state')}"]
  end

  def client_cmd(name, client)
    ["-#{name}_image #{client_snapshot(name)}",
     "-#{name}_memory #{client['memory']}",
     "-#{name}_cpus #{client['cpus']}"]
  end

  def clients_cmd
    clients = []
    @platform['clients'].each do |name, client|
      clients += client_cmd(name, client)
    end
    clients
  end

  def retrieve_pid(pid_file)
    Timeout.timeout(5) do
      sleep 1 while File.zero?(pid_file.path)
    end
    pid_file.read.strip.to_i
  rescue Timeout::Error
    nil
  end

  def run(name, first_time = false)
    sleep(rand(10))
    temp_file do |pid|
      cmd = base_cmd + clients_cmd + device_cmd +
            ["-pidfile #{pid.path}", name]
      create_command_file(cmd.join(' '), name) if first_time
      run_cmd(cmd)
      retrieve_pid(pid)
    end
  end

  def close
    @logger.info('Cleanup host configurations')
    cmd = base_cmd + device_cmd + ['end']
    run_cmd(cmd)
  end

  def create_client_snapshot(name)
    client = @platform['clients'][name]
    @logger.info("Creating #{client['name']} snapshot file")
    base = "#{@config['images_path']}/#{client['image']}"
    target = client_snapshot(name)
    create_snapshot_cmd(base, target)
  end

  def delete_client_snapshot(name)
    client = @platform['clients'][name]
    @logger.info("Deleting #{client['name']} snapshot file")
    target = client_snapshot(name)
    FileUtils.rm_f(target)
  end

  def create_studio_snapshot
    @logger.info('Creating studio snapshot file')
    base = "#{@config['images_path']}/#{@platform['st_image']}"
    target = studio_snapshot
    create_snapshot_cmd(base, target)
  end

  def delete_studio_snapshot
    @logger.info('Deleting studio snapshot file')
    target = studio_snapshot
    FileUtils.rm_f(target)
  end

  def create_snapshot_cmd(base, target)
    cmd = ["#{@config['qemu_img']} create -f qcow2 -F qcow2 -b", base, target]
    run_cmd(cmd)
  end

  def create_command_file(cmd, filename)
    path = "#{@workspace_path}/#{filename}.sh"
    File.open(path, 'w') { |file| file.write(cmd) }
    FileUtils.chmod('+x', path)
  end

  def normalize_paths
    @config['images_path'].chomp!('/')
    @config['virthck_path'].chomp!('/')
  end

  def validate_images
    unless File.exist?("#{@config['images_path']}/#{@platform['st_image']}")
      @logger.fatal('Studio image not found')
      raise InvalidPathError
    end
    @platform['clients'].each_value do |client|
      unless File.exist?("#{@config['images_path']}/#{client['image']}")
        @logger.fatal("#{client['name']} image not found")
        raise InvalidPathError
      end
    end
  end

  def create_studio
    studio_ip = @project.config['ip_segment'] + @project.id.to_str
    @studio = HCKStudio.new(@project, self, STUDIO, studio_ip)
  end

  def create_client(tag, name)
    HCKClient.new(@project, self, @studio, tag, name)
  end

  def validate_paths
    normalize_paths
    validate_images
    return if File.exist?("#{@config['virthck_path']}/hck.sh")

    @logger.fatal('VirtHCK path is not valid')
    raise InvalidPathError
  end
end
