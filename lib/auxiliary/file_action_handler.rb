# frozen_string_literal: true

module AutoHCK
  # Handles file transfer operations (upload/download) between local host and
  # remote guest machines, dispatching on FileActionConfig direction.
  class FileActionHandler
    def initialize(tools, logger)
      @tools = tools
      @logger = logger
    end

    def handle(machine_name, files_action)
      @logger.info("Running file action on #{machine_name} " \
                   "#{files_action.direction} from #{files_action.remote_path} to #{files_action.local_path}")

      case files_action.direction
      when Models::FileActionDirection::LocalToRemote
        run_local_to_remote(machine_name, files_action)
      when Models::FileActionDirection::RemoteToLocal
        run_remote_to_local(machine_name, files_action)
      else
        raise EngineError, "Unknown files_action direction: #{files_action.direction}"
      end
    end

    private

    def run_local_to_remote(machine_name, files_action)
      local_path = files_action.local_path

      unless File.exist?(local_path)
        if files_action.allow_missing
          @logger.warn("Local file not found, skipping: #{local_path}")
          return
        end

        raise EngineError, "Local file not found: #{local_path}"
      end

      @logger.debug("Uploading: #{local_path} -> #{files_action.remote_path}")
      @tools.upload_to_machine(machine_name, local_path, files_action.remote_path)
      FileUtils.rm_rf(local_path) if files_action.move
    end

    def run_remote_to_local(machine_name, files_action)
      remote_path = files_action.remote_path

      unless @tools.exists_on_machine?(machine_name, remote_path)
        if files_action.allow_missing
          @logger.warn("Remote file not found, skipping: #{remote_path}")
          return
        end

        raise EngineError, "Remote file not found on #{machine_name}: #{remote_path}"
      end

      local_path = files_action.local_path
      FileUtils.mkdir_p(File.dirname(local_path))
      @logger.debug("Downloading: #{remote_path} -> #{local_path}")
      @tools.download_from_machine(machine_name, remote_path, local_path)
      @tools.delete_on_machine(machine_name, remote_path) if files_action.move
    end
  end
end
