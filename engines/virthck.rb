# frozen_string_literal: true

require 'json'
require './lib/exceptions'

# Virthck class
class VirtHCK
  VIRTHCK_CONFIG_JSON = './engines/virthck.json'
  def initialize(project, id)
    @project = project
    @logger = project.logger
    @config = read_json(VIRTHCK_CONFIG_JSON)
    @device = project.device['device']
    @platform = project.platform
    @id = id
    validate_paths
  end

  def read_json(json_file)
    JSON.parse(File.read(json_file))
  rescue Errno::ENOENT, JSON::ParserError
    @logger.fatal("Could not open #{json_file} file")
    raise InvalidConfigFile
  end

  def studio_snapshot
    filename = File.basename(@project.platform['st_image'], '.*')
    @project.workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def client_snapshot(name)
    filename = File.basename(@project.platform['clients'][name]['image'], '.*')
    @project.workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def platform_config(param)
    default_value = @config['platforms_defaults'][param]
    @project.platform[param] || default_value
  end

  def base_cmd
    ["cd #{@config['virthck_path']} &&",
     "sudo ./hck.sh ci_mode -id #{@id}",
     "-world_bridge #{@config['dhcp_bridge']}",
     "-qemu_bin #{@config['qemu_bin']}",
     "-ivshmem_server_bin #{@config['ivshmem_server_bin']}",
     "-filesystem_tests_image #{@config['filesystem_tests_image']}",
     "-ctrl_net_device #{platform_config('ctrl_net_device')}",
     "-world_net_device #{platform_config('world_net_device')}",
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
    @project.platform['clients'].each do |name, client|
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

  def temp_file
    file = Tempfile.new('')
    yield(file)
  ensure
    file.close
    file.unlink
  end

  def run(name, first_time = false)
    temp_file do |pid|
      cmd = base_cmd + clients_cmd + device_cmd +
            ["-pidfile #{pid.path}", name]
      create_command_file(cmd.join(' '), name) if first_time
      run_cmd(cmd)
      retrieve_pid(pid)
    end
  end

  def close
    cmd = base_cmd + ['end']
    run_cmd(cmd)
  end

  def prep_stream_for_log(stream)
    stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
  end

  def log_stdout_stderr(stdout, stderr)
    unless stdout.empty?
      @logger.info('Info dump:' + prep_stream_for_log(stdout))
    end
    return if stderr.empty?

    @logger.warn('Error dump:' + prep_stream_for_log(stderr))
  end

  def run_cmd(cmd)
    temp_file do |stdout|
      temp_file do |stderr|
        Process.wait(spawn(cmd.join(' '), out: stdout.path, err: stderr.path))
        log_stdout_stderr(stdout.read, stderr.read)
        e_message = "Failed to run: #{cmd.join(' ')}"
        raise CmdRunError, e_message unless $CHILD_STATUS.exitstatus.zero?
      end
    end
  end

  def create_client_snapshot(name)
    client = @project.platform['clients'][name]
    @logger.info("Creating #{client['name']} snapshot file")
    base = "#{@config['images_path']}/#{client['image']}"
    target = client_snapshot(name)
    create_snapshot_cmd(base, target)
  end

  def delete_client_snapshot(name)
    client = @project.platform['clients'][name]
    @logger.info("Deleting #{client['name']} snapshot file")
    target = client_snapshot(name)
    FileUtils.rm_f(target)
  end

  def create_studio_snapshot
    @logger.info('Creating studio snapshot file')
    base = "#{@config['images_path']}/#{@project.platform['st_image']}"
    target = studio_snapshot
    create_snapshot_cmd(base, target)
  end

  def delete_studio_snapshot
    @logger.info('Deleting studio snapshot file')
    target = studio_snapshot
    FileUtils.rm_f(target)
  end

  def create_snapshot_cmd(base, target)
    cmd = ["#{@config['qemu_img']} create -f qcow2 -b", base, target]
    run_cmd(cmd)
  end

  def create_command_file(cmd, filename)
    path = "#{@project.workspace_path}/#{filename}.sh"
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

  def validate_paths
    normalize_paths
    validate_images
    return if File.exist?("#{@config['virthck_path']}/hck.sh")

    @logger.fatal('VirtHCK path is not valid')
    raise InvalidPathError
  end
end
