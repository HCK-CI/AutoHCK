require './lib/id_gen.rb'

# Virthck class
class VirtHCK
  attr_reader :id
  def initialize(project)
    @project = project
    @logger = project.logger
    @config = project.config
    @device = project.device['device']
    @id_gen = Idgen.new(project)
    @id = assign_id
  end

  def assign_id
    @id = @id_gen.allocate
    if @id < 0
      @logger.fatal('No available ID, wait for a test session to end')
      exit 1
    end
    @logger.info("Assinged ID: #{@id}")
    @id.to_s
  end

  def release_id
    @logger.info("Releasing ID: #{@id}")
    @id_gen.release(@id)
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
    default_value = @project.config['platforms_defaults'][param]
    @project.platform[param] || default_value
  end

  def base_cmd
    ["cd #{@project.config['virthck_path']} &&",
     "sudo ./hck.sh ci_mode -id #{@id}",
     "-world_bridge #{@project.config['dhcp_bridge']}",
     "-qemu_bin #{@project.config['qemu_bin']}",
     "-ivshmem_server_bin #{@project.config['ivshmem_server_bin']}",
     "-filesystem_tests_image #{@project.config['filesystem_tests_image']}",
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
    release_id
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

    @logger.error('Error dump:' + prep_stream_for_log(stderr))
  end

  def run_cmd(cmd)
    temp_file do |stdout|
      temp_file do |stderr|
        Process.wait(spawn(cmd.join(' '), out: stdout.path, err: stderr.path))
        log_stdout_stderr(stdout.read, stderr.read)
        raise "Failed to run: #{cmd}" unless $CHILD_STATUS.exitstatus.zero?
      end
    end
  end

  def create_client_snapshot(name)
    client = @project.platform['clients'][name]
    @logger.info("Creating #{client['name']} snapshot file")
    base = "#{@project.config['images_path']}/#{client['image']}"
    target = client_snapshot(name)
    create_snapshot_cmd(base, target)
  end

  def create_studio_snapshot
    @logger.info('Creating studio snapshot file')
    base = "#{@project.config['images_path']}/#{@project.platform['st_image']}"
    target = studio_snapshot
    create_snapshot_cmd(base, target)
  end

  def create_snapshot_cmd(base, target)
    cmd = ["#{@project.config['qemu_img']} create -f qcow2 -b", base, target]
    run_cmd(cmd)
  end

  def create_command_file(cmd, filename)
    path = "#{@project.workspace_path}/#{filename}.sh"
    File.open(path, 'w') { |file| file.write(cmd) }
    FileUtils.chmod('+x', path)
  end

  def machine_alive?(name)
    `ps -A -o cmd | grep '[\-]name #{name}'`.split("\n").any?
  end

  def client_alive?(name)
    id = name[-1]
    s_id = @id.to_s.rjust(4, '0')
    machine_alive?("HCK-Client#{id}_#{s_id}")
  end

  def studio_alive?
    s_id = @id.to_s.rjust(4, '0')
    machine_alive?("HCK-Studio_#{s_id}")
  end
end
