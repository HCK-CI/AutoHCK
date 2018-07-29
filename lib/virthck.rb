# Virthck class
class VirtHCK
  attr_reader :id
  def initialize(project)
    @project = project
    @logger = project.logger
    @config = project.config
    @device = project.device['device']
    @id = project.platform['id']
  end

  def assign_id
    id_range = [*@config['id_range'].first..@config['id_range'].last]
    available_ids = id_range - alive_ids
    if available_ids.empty?
      @logger.fatal('No available ID, wait for a test session to end')
      exit 1
    end
    @logger.info("Assinged ID: #{available_ids.first}")
    @id = available_ids.first.to_s
  end

  def alive_ids
    bash_command = "sudo ps aux | grep ' [\-]name HCK' | "\
                   "grep -o ' [\-]uuid 00[0-9]\\{2\\}' | grep -o '..$'"
    `#{bash_command}`.split(/\n/).map(&:to_i)
  end

  def studio_snapshot
    filename = File.basename(@project.platform['st_image'], '.*')
    @project.workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def client_snapshot(name)
    filename = File.basename(@project.platform['clients'][name]['image'], '.*')
    @project.workspace_path + '/' + filename + '-snapshot.qcow2'
  end

  def base_cmd
    ["cd #{@project.config['virthck_path']} &&",
     "sudo ./hck.sh ci_mode -id #{@id}",
     "-world_bridge #{@project.config['dhcp_bridge']}",
     "-qemu_bin #{@project.config['qemu_bin']}",
     "-ctrl_net_device #{@project.platform['ctrl_net_device']}",
     "-world_net_device #{@project.platform['world_net_device']}",
     "-file_transfer_device #{@project.platform['file_transfer_device']}",
     "-st_image #{studio_snapshot}"]
  end

  def device_cmd
    ["-device_type #{@device['type']}",
     !@device['name'].empty? ? "-device_name #{@device['name']}" : '',
     !@device['extra'].empty? ? "-device_extra #{@device['extra']}" : '']
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

  def run(name, first_time = false)
    cmd = base_cmd + clients_cmd + device_cmd + [name]
    create_command_file(cmd.join(' '), name) if first_time
    run_cmd(cmd)
  end

  def close
    cmd = base_cmd + ['end']
    run_cmd(cmd)
  end

  def run_cmd(cmd)
    system((cmd + [' > /dev/null']).join(' '))
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

  def client_alive?(name)
    id = name[-1]
    s_id = @id.to_s.rjust(4, '0')
    `ps -A -o cmd | grep '[\-]name HCK-Client#{id}_#{s_id}'`.split("\n").any?
  end
end
