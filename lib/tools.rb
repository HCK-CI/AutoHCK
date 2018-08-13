require 'rtoolsHCK'
require 'nori/parser/rexml'

# Tools class
class Tools < RToolsHCK
  def initialize(project, ip_addr)
    @logger = project.logger
    config = project.config
    connect(addr: ip_addr,
            user: config['studio_username'],
            pass: config['studio_password'],
            winrm_ports: config_winrm_ports(project),
            logger: @logger,
            outp_dir: project.workspace_path,
            script_file: config['toolshck_path'])
  end

  def connect(conn)
    @tools = RToolsHCK.new(conn)
  end

  def config_winrm_ports(project)
    winrm_ports = {}
    project.platform['clients'].each_value do |client|
      winrm_ports[client['name']] = client['winrm_port']
    end
    winrm_ports
  end

  def handle_results(results)
    return results['content'] unless results['result'] == 'Failure'
    @logger.error(results['message'])
    raise results['message']
  end

  def create_pool(tag)
    handle_results(@tools.create_pool(tag, :json))
  end

  def create_project(tag)
    handle_results(@tools.create_project(tag, :json))
  end

  def list_pools
    handle_results(@tools.list_pools(:json))
  end

  def create_project_target(key, tag, machine)
    handle_results(@tools.create_project_target(key, tag, machine, tag, :json))
  end

  def list_machine_targets(machine, pool)
    handle_results(@tools.list_machine_targets(machine, pool, :json))
  end

  def delete_machine(machine, pool)
    handle_results(@tools.delete_machine(machine, pool, :json))
  end

  def restart_machine(machine)
    handle_results(@tools.machine_shutdown(machine, :restart, :json))
  end

  def shutdown_machine(machine)
    handle_results(@tools.machine_shutdown(machine, :shutdown, :json))
  end

  def shutdown
    handle_results(@tools.shutdown(false, :json))
  end

  def move_machine(machine, from, to)
    handle_results(@tools.move_machine(machine, from, to, :json))
  rescue StandardError => e
    @logger.error("#{e.class}: #{e}")
  end

  def set_machine_ready(machine, pool)
    handle_results(@tools.set_machine_state(machine, pool, 'ready', nil, :json))
  rescue StandardError => e
    @logger.error("#{e.class}: #{e}")
  end

  def install_machine_driver_package(machine, method, driver_path, file)
    handle_results(@tools.install_machine_driver_package(machine, driver_path,
                                                         method, file, :json))
  end

  def list_tests(key, machine, tag, playlist)
    handle_results(@tools.list_tests(key, tag, machine, tag, nil, nil,
                                     playlist,
                                     :json))
  end

  def queue_test(test_id, target_key, machine, tag, support)
    handle_results(@tools.queue_test(test_id, target_key, tag, machine, tag,
                                     support,
                                     nil,
                                     :json))
  end

  def get_test_results(test_id, target_key, machine, tag)
    handle_results(@tools.get_test_results(test_id, target_key, tag, machine,
                                           tag, :json))
  rescue StandardError
    @logger.info('Archiving tests results failed, trying again.')
    sleep 10
    retry
  end

  def create_project_package(project, handler = nil)
    handle_results(@tools.create_project_package(project, handler, :json))
  end
end
