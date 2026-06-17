# frozen_string_literal: true

module AutoHCK
  # Collects Windows minidump files from one or more guest machines, zips them,
  # and returns the zip path (or nil if no dumps were found).
  #
  # Used by both HCKTest and FunctestEngine after each test so that BSOD
  # evidence is captured regardless of which engine is running.
  class MemoryDumpCollector
    include Helper

    MINIDUMP_PATH = '${env:SystemRoot}/Minidump'

    def initialize(tools, machine_names, workspace_path, logger)
      @tools = tools
      @machine_names = machine_names
      @workspace_path = workspace_path
      @logger = logger
    end

    # Download minidumps from all machines, zip them, and return the zip path.
    # Returns the zip path (String) if dumps were found, nil otherwise.
    def collect(id)
      tmp_path = "#{@workspace_path}/tmp_#{id}"
      zip_path = "#{@workspace_path}/memory_dump_#{id}.zip"

      if fetch_all_dumps(tmp_path)
        create_zip_from_directory(zip_path, tmp_path)
        return zip_path
      end

      nil
    ensure
      FileUtils.rm_rf(tmp_path)
    end

    private

    def fetch_all_dumps(tmp_path)
      @machine_names.any? do |machine|
        fetch_machine_dump(machine, "#{tmp_path}/#{machine}_#{current_timestamp}")
      end
    end

    def fetch_machine_dump(machine, machine_tmp_path)
      exist = @tools.exists_on_machine?(machine, MINIDUMP_PATH)
      @logger.debug("Checking Minidump on #{machine}: #{exist}")
      return false unless exist

      @logger.info("Downloading memory dump (Minidump) from #{machine}")
      @tools.download_from_machine(machine, MINIDUMP_PATH, machine_tmp_path)
      @tools.delete_on_machine(machine, MINIDUMP_PATH)
      true
    end
  end
end
