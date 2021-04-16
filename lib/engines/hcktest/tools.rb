# frozen_string_literal: true

require 'rtoolsHCK'
require 'nori/parser/rexml'

# AutoHCK module
module AutoHCK
  # Tools class
  class Tools
    ACTION_RETRIES = 5
    ACTION_RETRY_SLEEP = 10
    def initialize(project, ip_addr, clients)
      @logger = project.logger
      @config = project.config
      @clients = clients
      validate_paths
      connect(addr: ip_addr,
              user: @config['studio_username'],
              pass: @config['studio_password'],
              winrm_ports: config_winrm_ports,
              timeout: 120,
              logger: @logger,
              outp_dir: project.workspace_path,
              l_script_file: @config['toolshck_path'])
    end

    # A custom InvalidToolsPath error exception
    class InvalidToolsPathError < AutoHCKError; end

    # A custom ZipTestResultLogs error exception
    class ZipTestResultLogsError < AutoHCKError; end

    # A custom RestartMachine error exception
    class RestartMachineError < AutoHCKError; end

    # A custom RunOnMachine error exception
    class RunOnMachineError < AutoHCKError; end

    # A custom UploadToMachineError error exception
    class UploadToMachineError < AutoHCKError; end

    # A custom DownloadFromMachineError error exception
    class DownloadFromMachineError < AutoHCKError; end

    # A custom ExistsOnMachineError error exception
    class ExistsOnMachineError < AutoHCKError; end

    # A custom DeleteOnMachineError error exception
    class DeleteOnMachineError < AutoHCKError; end

    # A custom ShutdownMachine error exception
    class ShutdownMachineError < AutoHCKError; end

    # A custom InstallMachineDriverPackage error exception
    class InstallMachineDriverPackageError < AutoHCKError; end

    # A thread safe class that wraps an object instace with critical data
    class ThreadSafe < BasicObject
      def initialize(object, mutex)
        @delegate = object
        @mutex = mutex
      end

      def method_missing(method, *args, &block)
        if @delegate.respond_to?(method)
          @mutex.synchronize { @delegate.send(method, *args, &block) }
        else
          super
        end
      end

      def respond_to_missing?(method, *args)
        @delegate.respond_to?(method) || super
      end
    end

    def connect(conn)
      @tools = ThreadSafe.new(RToolsHCK.new(conn), Mutex.new)
    end

    def config_winrm_ports
      winrm_ports = {}
      @clients.each_value do |client|
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
        nil
      else
        results['content'].nil? ? true : results['content']
      end
    end

    def create_pool(tag)
      handle_results(@tools.create_pool(tag))
    end

    def delete_pool(tag)
      handle_results(@tools.delete_pool(tag))
    end

    def create_project(tag)
      handle_results(@tools.create_project(tag))
    end

    def delete_project(tag)
      handle_results(@tools.delete_project(tag))
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
      @logger.info("Trying again to run command (#{desc}) on machine #{machine}")
      retry
    end

    def upload_to_machine(machine, l_directory)
      retries ||= 0
      ret = handle_results(@tools.upload_to_machine(machine, l_directory))

      return ret if ret

      e_message = "Upload to machine #{machine} failed"
      raise UploadToMachineError, e_message
    rescue UploadToMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again upload to machine #{machine}")
      retry
    end

    def download_from_machine(machine, r_path, l_path)
      retries ||= 0
      ret = handle_results(@tools.download_from_machine(machine, r_path, l_path))

      return ret if ret

      e_message = "Download from machine #{machine} failed"
      raise DownloadFromMachineError, e_message
    rescue DownloadFromMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again download from machine #{machine}")
      retry
    end

    def exists_on_machine?(machine, r_path)
      retries ||= 0
      ret = handle_results(@tools.exists_on_machine?(machine, r_path))

      return ret unless ret.nil?

      e_message = "Checking exists on machine #{machine} failed"
      raise ExistsOnMachineError, e_message
    rescue ExistsOnMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again check exists on machine #{machine}")
      retry
    end

    def delete_on_machine(machine, r_path)
      retries ||= 0
      ret = handle_results(@tools.delete_on_machine(machine, r_path))

      return ret if ret

      e_message = "delete_on_machine #{machine} failed"
      raise DeleteOnMachineError, e_message
    rescue DeleteOnMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again delete_on_machine #{machine}")
      retry
    end

    def restart_machine(machine)
      retries ||= 0
      ret = handle_results(@tools.machine_shutdown(machine, restart: true))

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
      ret = handle_results(@tools.machine_shutdown(machine))

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
      handle_results(@tools.shutdown)
    end

    def move_machine(machine, from, to)
      handle_results(@tools.move_machine(machine, from, to))
    end

    # Timeout for setting a machine state to the Ready state
    SET_MACHINE_READY_TIMEOUT = 120

    def set_machine_ready(machine, pool)
      handle_results(@tools.set_machine_state(machine,
                                              pool,
                                              'ready',
                                              SET_MACHINE_READY_TIMEOUT))
    end

    def install_machine_driver_package(machine, method, driver_path, file, custom_cmd = nil)
      retries ||= 0
      ret = handle_results(@tools.install_machine_driver_package(machine,
                                                                 driver_path,
                                                                 method, file, custom_cmd))

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

    def get_test_info(id, key, machine, tag)
      handle_results(@tools.get_test_info(id, key, tag, machine, tag))
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

    def connection_check
      handle_results(@tools.connection_check)
    end

    def reconnect
      handle_results(@tools.reconnect)
    end

    def close
      @tools&.close
      @tools = nil
    end

    def validate_paths
      return if File.exist?(@config['toolshck_path'])

      @logger.fatal('toolsHCK script path is not valid')
      raise InvalidToolsPathError, 'toolsHCK script path is not valid'
    end
  end
end
