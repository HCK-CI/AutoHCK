# frozen_string_literal: true

# AutoHCK module
module AutoHCK
  # Tools class
  class Tools
    ACTION_RETRIES = 5
    HLK_ACTION_RETRY_SLEEP = 10
    ACTION_RETRY_SLEEP = 90
    def initialize(project, ip_addr, clients)
      @logger = project.logger
      @config = project.config
      @clients = clients
      connect(addr: ip_addr,
              user: @config['studio_username'],
              pass: @config['studio_password'],
              winrm_ports: config_winrm_ports,
              timeout: 120,
              logger: @logger,
              outp_dir: project.workspace_path)
    end

    # A custom ZipTestResultLogs error exception
    class ZipTestResultLogsError < AutoHCKError; end

    # A custom RestartMachine error exception
    class RestartMachineError < AutoHCKError; end

    # A custom RunOnMachine error exception
    class RunOnMachineError < AutoHCKError; end

    # A custom RunOnStudio error exception
    class RunOnStudioError < AutoHCKError; end

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

    # A custom SystemInfoMachineError error exception
    class SystemInfoMachineError < AutoHCKError; end

    # A custom InstallMachineDriverPackage error exception
    class InstallMachineDriverPackageError < AutoHCKError; end

    # A thread safe class that wraps an object instace with critical data
    class ThreadSafe < BasicObject
      def initialize(object, mutex)
        @delegate = object
        @mutex = mutex
      end

      def synchronize
        @mutex.synchronize { yield @delegate }
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

    def act_with_tools(&)
      results = @tools.synchronize(&)

      if results['result'] == 'Failure'
        if results['message']
          failure_message = prep_stream_for_log(results['message'])
          @logger.warn("Tools action failure#{failure_message}")
        end
        nil
      else
        results['content'].nil? || results['content']
      end
    end

    def retry_tools_command(action)
      ret = nil

      ACTION_RETRIES.times do
        ret = yield

        break if ret

        @logger.warn("Running HLK tools command (#{action}) failed")
        sleep HLK_ACTION_RETRY_SLEEP
        @logger.info("Trying again to run HLK tools command (#{action})")
      rescue StandardError => e
        @logger.warn("Running HLK tools command (#{action}) failed with #{e}")
        sleep HLK_ACTION_RETRY_SLEEP
        @logger.info("Trying again to run HLK tools command (#{action})")
      end

      ret
    end

    def create_pool(tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.create_pool(tag) }
      end
    end

    def delete_pool(tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.delete_pool(tag) }
      end
    end

    def create_project(tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.create_project(tag) }
      end
    end

    def delete_project(tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.delete_project(tag) }
      end
    end

    def list_pools
      retry_tools_command(__method__) do
        act_with_tools(&:list_pools)
      end
    end

    def create_project_target(key, tag, machine)
      retry_tools_command(__method__) do
        act_with_tools { _1.create_project_target(key, tag, machine, tag) }
      end
    end

    def list_machine_targets(machine, pool)
      retry_tools_command(__method__) do
        act_with_tools { _1.list_machine_targets(machine, pool) }
      end
    end

    def delete_machine(machine, pool)
      retry_tools_command(__method__) do
        act_with_tools { _1.delete_machine(machine, pool) }
      end
    end

    def run_on_studio(command)
      retries ||= 0
      ret = act_with_tools { _1.run_on_studio(command) }

      return ret if ret

      e_message = "Running command (#{command}) on studio failed"
      raise RunOnStudioError, e_message
    rescue RunOnStudioError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again to run command (#{command}) on studio")
      retry
    end

    def run_on_machine(machine, desc, cmd)
      retries ||= 0
      ret = act_with_tools { _1.run_on_machine(machine, cmd) }

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

    def upload_to_machine(machine, l_directory, r_directory = nil)
      retries ||= 0
      ret = act_with_tools { _1.upload_to_machine(machine, l_directory, r_directory) }

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
      ret = act_with_tools { _1.download_from_machine(machine, r_path, l_path) }

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
      ret = act_with_tools { _1.exists_on_machine?(machine, r_path) }

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
      ret = act_with_tools { _1.delete_on_machine(machine, r_path) }

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
      ret = act_with_tools { _1.machine_shutdown(machine, restart: true) }

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
      ret = act_with_tools { _1.machine_shutdown(machine) }

      return ret if ret

      raise ShutdownMachineError, "Shuting down machine #{machine} failed"
    rescue ShutdownMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again to shutdown machine #{machine}")
      retry
    end

    def get_machine_system_info(machine, output_format = 'CSV')
      retries ||= 0
      ret = act_with_tools { _1.get_machine_system_info(machine, output_format) }

      return ret if ret

      raise SystemInfoMachineError, "Getting machine #{machine} system info failed"
    rescue SystemInfoMachineError => e
      @logger.warn(e.message)
      raise unless (retries += 1) < ACTION_RETRIES

      sleep ACTION_RETRY_SLEEP
      @logger.info("Trying again to get machine #{machine} system info")
      retry
    end

    def shutdown
      retry_tools_command(__method__) do
        act_with_tools(&:shutdown)
      end
    end

    def move_machine(machine, from, to)
      retry_tools_command(__method__) do
        act_with_tools { _1.move_machine(machine, from, to) }
      end
    end

    # Timeout for setting a machine state to the Ready state
    SET_MACHINE_READY_TIMEOUT = 120

    def set_machine_ready(machine, pool)
      retry_tools_command(__method__) do
        act_with_tools { _1.set_machine_state(machine, pool, 'ready', SET_MACHINE_READY_TIMEOUT) }
      end
    end

    def install_machine_driver_package(machine, method, driver_path, file, options = {})
      retries ||= 0
      ret = act_with_tools { _1.install_machine_driver_package(machine, method, driver_path, file, options) }

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
      tests = retry_tools_command(__method__) do
        act_with_tools { _1.list_tests(key, tag, machine, tag, nil, nil, playlist) }
      end

      tests.map { Models::HLK::Test.from_hash(_1) }
    end

    def list_test_results(test_id, target_key, machine, tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.list_test_results(test_id, target_key, tag, machine, tag) }
      end
    end

    def list_all_results(target_key, machine, tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.list_test_results(nil, target_key, tag, machine, tag) }
      end
    end

    def get_test_info(id, key, machine, tag)
      retry_tools_command(__method__) do
        act_with_tools { _1.get_test_info(id, key, tag, machine, tag) }
      end
    end

    def queue_test(test_id:, target_key:, tag:, machine:, support:, parameters:) # rubocop:disable Metrics/ParameterLists
      retry_tools_command(__method__) do
        act_with_tools { _1.queue_test(test_id, target_key, tag, machine, tag, support, parameters) }
      end
    end

    def update_filters(filters_path)
      retry_tools_command(__method__) do
        act_with_tools { _1.update_filters(filters_path) }
      end
    end

    def apply_project_filters(project)
      retry_tools_command(__method__) do
        act_with_tools { _1.apply_project_filters(project) }
      end
    end

    def zip_test_result_logs(...)
      retries ||= 0
      ret = act_with_tools { _1.zip_test_result_logs(...) }

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

    def create_project_package(project, playlist = nil, handler = nil)
      retry_tools_command(__method__) do
        act_with_tools { _1.create_project_package(project, playlist, handler) }
      end
    end

    def connection_check
      retry_tools_command(__method__) do
        act_with_tools(&:connection_check)
      end
    end

    def reconnect
      retry_tools_command(__method__) do
        act_with_tools(&:reconnect)
      end
    end

    def close
      @tools&.synchronize(&:close)
      @tools = nil
    end
  end
end
