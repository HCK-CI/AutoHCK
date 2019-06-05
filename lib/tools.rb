# frozen_string_literal: true

require 'rtoolsHCK'
require 'nori/parser/rexml'

# Tools class
class Tools < RToolsHCK
  ACTION_RETRIES = 5
  ACTION_RETRY_SLEEP = 10
  def initialize(project, ip_addr)
    @logger = project.logger
    config = project.config
    connect(addr: ip_addr,
            user: config['studio_username'],
            pass: config['studio_password'],
            winrm_ports: config_winrm_ports(project),
            timeout: 120,
            logger: @logger,
            outp_dir: project.workspace_path,
            script_file: config['toolshck_path'])
  end

  # A custom ZipTestResultLogs error exception
  class ZipTestResultLogsError < AutoHCKError; end

  # A custom RestartMachine error exception
  class RestartMachineError < AutoHCKError; end

  # A custom RunOnMachine error exception
  class RunOnMachineError < AutoHCKError; end

  # A custom ShutdownMachine error exception
  class ShutdownMachineError < AutoHCKError; end

  # A custom InstallMachineDriverPackage error exception
  class InstallMachineDriverPackageError < AutoHCKError; end

  # A thread safe class that wraps an object instace with critical data
  class ThreadSafe < BasicObject
    def initialize(object)
      @delegate = object
    end

    def method_missing(method, *args, &block)
      if @delegate.respond_to?(method)
        @delegate.mu_synchronize { @delegate.send(method, *args, &block) }
      else
        super
      end
    end

    def respond_to_missing?(method, *args)
      @delegate.respond_to?(method) || super
    end
  end

  def connect(conn)
    tools = RToolsHCK.new(conn)
    tools.extend(Mutex_m)
    @tools = ThreadSafe.new(tools)
  end

  def config_winrm_ports(project)
    winrm_ports = {}
    project.platform['clients'].each_value do |client|
      winrm_ports[client['name']] = client['winrm_port']
    end
    winrm_ports
  end

  def prep_stream_for_log(stream)
    stream.strip.lines.map { |line| "\n   -- #{line.rstrip}" }.join
  end

  def handle_results(results)
    if results['result'] == 'Failure'
      if results['message']
        failure_message = prep_stream_for_log(results['message'])
        @logger.warn("Tools action failure#{failure_message}")
      end
      false
    else
      results['content'] || true
    end
  end

  def create_pool(tag)
    handle_results(@tools.create_pool(tag))
  end

  def create_project(tag)
    handle_results(@tools.create_project(tag))
  end

  def list_pools
    handle_results(@tools.list_pools)
  end

  def create_project_target(key, tag, machine)
    handle_results(@tools.create_project_target(key, tag, machine, tag))
  end

  def list_machine_targets(machine, pool)
    handle_results(@tools.list_machine_targets(machine, pool))
  end

  def delete_machine(machine, pool)
    handle_results(@tools.delete_machine(machine, pool))
  end

  def run_on_machine(machine, desc, cmd)
    retries ||= 0
    ret = handle_results(@tools.run_on_machine(machine, cmd))

    return ret if ret

    e_message = "Running command (#{desc}) on machine #{machine} failed"
    raise RunOnMachineError, e_message
  rescue RunOnMachineError => e
    @logger.warn(e.message)
    raise unless (retries += 1) < ACTION_RETRIES

    sleep ACTION_RETRY_SLEEP
    @logger.inf("Trying again to run command (#{desc}) on machine #{machine}")
    retry
  end

  def restart_machine(machine)
    retries ||= 0
    ret = handle_results(@tools.machine_shutdown(machine, :restart))

    return ret if ret

    raise RestartMachineError, "Restarting machine #{machine} failed"
  rescue RestartMachineError => e
    @logger.warn(e.message)
    raise unless (retries += 1) < ACTION_RETRIES

    sleep ACTION_RETRY_SLEEP
    @logger.info("Trying again to restart machine #{machine}")
    retry
  end

  def shutdown_machine(machine)
    retries ||= 0
    ret = handle_results(@tools.machine_shutdown(machine, :shutdown))

    return ret if ret

    raise ShutdownMachineError, "Shuting down machine #{machine} failed"
  rescue ShutdownMachineError => e
    @logger.warn(e.message)
    raise unless (retries += 1) < ACTION_RETRIES

    sleep ACTION_RETRY_SLEEP
    @logger.info("Trying again to shutdown machine #{machine}")
    retry
  end

  def shutdown
    handle_results(@tools.shutdown(false))
  end

  def move_machine(machine, from, to)
    handle_results(@tools.move_machine(machine, from, to))
  end

  def set_machine_ready(machine, pool)
    handle_results(@tools.set_machine_state(machine, pool, 'ready', -1))
  end

  def install_machine_driver_package(machine, method, driver_path, file)
    retries ||= 0
    ret = handle_results(@tools.install_machine_driver_package(machine,
                                                               driver_path,
                                                               method, file))

    return ret if ret

    e_message = "Installing driver package on machine #{machine} failed"
    raise InstallMachineDriverPackageError, e_message
  rescue InstallMachineDriverPackageError => e
    @logger.warn(e.message)
    raise unless (retries += 1) < ACTION_RETRIES

    sleep ACTION_RETRY_SLEEP
    @logger.info("Trying again to install driver package on machine #{machine}")
    retry
  end

  def list_tests(key, machine, tag, playlist)
    handle_results(@tools.list_tests(key, tag, machine, tag, nil, nil,
                                     playlist))
  end

  def queue_test(test_id, target_key, machine, tag, support)
    handle_results(@tools.queue_test(test_id, target_key, tag, machine, tag,
                                     support))
  end

  def update_filters(filters_path)
    handle_results(@tools.update_filters(filters_path))
  end

  def apply_project_filters(project)
    handle_results(@tools.apply_project_filters(project))
  end

  def zip_test_result_logs(test_id, target_key, machine, tag)
    retries ||= 0
    ret = handle_results(@tools.zip_test_result_logs(-1, test_id, target_key,
                                                     tag, machine, tag))

    return ret if ret

    raise ZipTestResultLogsError, 'Archiving tests results failed'
  rescue ZipTestResultLogsError => e
    # Results archiving might fail because they requested before they are done
    # or when the test itself didn't run and there are no results.
    @logger.warn(e.message)
    raise unless (retries += 1) < ACTION_RETRIES

    sleep ACTION_RETRY_SLEEP
    @logger.info('Trying again to archive tests results')
    retry
  end

  def create_project_package(project, handler = nil)
    handle_results(@tools.create_project_package(project, handler))
  end

  def close
    @toolsi&.close
  end
end
